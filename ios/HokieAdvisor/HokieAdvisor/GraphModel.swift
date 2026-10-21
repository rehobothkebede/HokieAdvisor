import CoreGraphics
import Foundation

/// A small graph described by a ```graph fenced block in an advisor answer.
///
/// Syntax (the chat system prompt documents the same format):
///
///     directed: true            # optional; any "->" edge also makes the graph directed
///     A - B : 4                 # undirected edge with weight 4 ("--" works too)
///     A -> B                    # directed edge, drawn with an arrowhead
///     CS-1114 -> CS-2114        # operators need spaces around them, so names can contain hyphens
///     "Data Structures" -> Algorithms
///     E                         # a node with no edges
///     highlight: A -> B -> D    # a path (nodes and the edges between them)
///     step: A | Start at A      # stepper frames: the nodes/path to highlight, then an optional caption
///     step: A, B, C | Visit A's neighbors
///     steps: A; A, B; A, B, C   # one-line alternative to repeated step: lines
///
/// Older unspaced forms ("A-B", "A->B", "highlight: A B D") are still read.
nonisolated struct SimpleGraph: Equatable {
    struct Edge: Hashable {
        let from: String
        let to: String
        let weight: String?
        let directed: Bool
    }

    /// An unordered node pair, used to match highlighted paths to edges.
    struct NodePair: Hashable {
        let a: String
        let b: String

        init(_ x: String, _ y: String) {
            if x <= y { a = x; b = y } else { a = y; b = x }
        }
    }

    struct Highlight: Equatable {
        var nodes: [String] = []
        var pairs: Set<NodePair> = []

        var isEmpty: Bool { nodes.isEmpty && pairs.isEmpty }
    }

    struct Step: Equatable {
        let highlight: Highlight
        let caption: String?
    }

    static let maxNodes = 40
    static let maxEdges = 120

    let nodes: [String]
    let edges: [Edge]
    let isDirected: Bool
    let highlight: Highlight
    let steps: [Step]
    /// Node centers in a unit square, from a layered layout for trees or a
    /// force-directed layout otherwise.
    let unitPositions: [String: CGPoint]
    let isTree: Bool
    let layerCount: Int

    // MARK: - Parsing

    /// Returns nil when the block has no nodes or is too large to draw legibly;
    /// callers show the raw text instead.
    static func parse(_ text: String) -> SimpleGraph? {
        var nodes: [String] = []
        var seen = Set<String>()
        var edges: [Edge] = []
        var forceDirected = false
        var highlightSpecs: [String] = []
        var stepSpecs: [(spec: String, caption: String?)] = []

        func addNode(_ name: String) {
            guard !name.isEmpty, !seen.contains(name) else { return }
            seen.insert(name)
            nodes.append(name)
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !isMermaidHeader(line) else { continue }

            if let value = directive("directed", in: line) {
                forceDirected = ["true", "yes", "1"].contains(value.lowercased())
                continue
            }
            if let value = directive("highlight", in: line) {
                highlightSpecs.append(value)
                continue
            }
            if let value = directive("steps", in: line) {
                for part in value.split(separator: ";") {
                    let spec = part.trimmingCharacters(in: .whitespaces)
                    if !spec.isEmpty { stepSpecs.append((spec, nil)) }
                }
                continue
            }
            if let value = directive("step", in: line) {
                let pieces = value.split(separator: "|", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard let spec = pieces.first, !spec.isEmpty else { continue }
                stepSpecs.append((spec, pieces.count > 1 && !pieces[1].isEmpty ? pieces[1] : nil))
                continue
            }

            if let parsed = parseEdgeLine(line) {
                for name in parsed.names { addNode(name) }
                for pair in zip(parsed.names, parsed.names.dropFirst()) {
                    edges.append(Edge(from: pair.0, to: pair.1, weight: parsed.weight, directed: parsed.directed))
                }
            } else {
                addNode(unquote(line))
            }
        }

        guard !nodes.isEmpty, nodes.count <= maxNodes, edges.count <= maxEdges else { return nil }
        // A block with no edges and sentence-like "nodes" is prose, not a graph.
        if edges.isEmpty, nodes.contains(where: { $0.count > 30 || $0.split(separator: " ").count > 4 || $0.contains(":") }) {
            return nil
        }

        let isDirected = forceDirected || edges.contains(where: \.directed)
        if forceDirected {
            edges = edges.map { Edge(from: $0.from, to: $0.to, weight: $0.weight, directed: true) }
        }

        let known = Set(nodes)
        var highlight = Highlight()
        for spec in highlightSpecs {
            let parsed = parseHighlight(spec, known: known)
            highlight.nodes.append(contentsOf: parsed.nodes.filter { !highlight.nodes.contains($0) })
            highlight.pairs.formUnion(parsed.pairs)
        }
        let steps = stepSpecs.map { Step(highlight: parseHighlight($0.spec, known: known), caption: $0.caption) }

        let layout = Layout.compute(nodes: nodes, edges: edges, isDirected: isDirected)
        return SimpleGraph(
            nodes: nodes,
            edges: edges,
            isDirected: isDirected,
            highlight: highlight,
            steps: steps,
            unitPositions: layout.positions,
            isTree: layout.isTree,
            layerCount: layout.layerCount
        )
    }

    func isHighlighted(_ edge: Edge, in highlight: Highlight) -> Bool {
        highlight.pairs.contains(NodePair(edge.from, edge.to))
    }

    /// Maps unit positions into a drawing rect inset by `inset` on every side.
    func positions(in size: CGSize, inset: CGFloat) -> [String: CGPoint] {
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        return unitPositions.mapValues { point in
            CGPoint(x: inset + point.x * width, y: inset + point.y * height)
        }
    }

    // MARK: - Line parsing

    private static let spacedOperator = try! NSRegularExpression(
        pattern: #"\s+(<->|-->|->|→|---|--|—|-)\s+"#
    )

    private struct EdgeLine {
        let names: [String]
        let weight: String?
        let directed: Bool
    }

    private static func parseEdgeLine(_ line: String) -> EdgeLine? {
        let (body, weight) = splitWeight(line)
        let quoted = quotedRanges(in: body)
        let range = NSRange(body.startIndex..., in: body)
        let matches = spacedOperator.matches(in: body, range: range).filter { match in
            !quoted.contains { NSIntersectionRange($0, match.range).length > 0 }
        }

        if !matches.isEmpty {
            var names: [String] = []
            var directed = false
            var cursor = body.startIndex
            for match in matches {
                guard let whole = Range(match.range, in: body),
                      let op = Range(match.range(at: 1), in: body) else { continue }
                names.append(unquote(String(body[cursor..<whole.lowerBound])))
                let symbol = body[op]
                if symbol == "->" || symbol == "-->" || symbol == "→" { directed = true }
                cursor = whole.upperBound
            }
            names.append(unquote(String(body[cursor...])))
            names = names.filter { !$0.isEmpty }
            return names.count >= 2 ? EdgeLine(names: names, weight: weight, directed: directed) : nil
        }

        // Legacy unspaced forms: "A->B", "A--B", "A-B". A lone course code
        // such as "CS-1114" is a node, not an edge between "CS" and "1114".
        for symbol in ["-->", "->", "---", "--", "-"] where body.contains(symbol) {
            let parts = body.components(separatedBy: symbol)
                .map { unquote($0) }
            guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            if symbol == "-", parts.count == 2, looksLikeCourseCode(parts[0], parts[1]) { return nil }
            return EdgeLine(names: parts, weight: weight, directed: symbol == "->" || symbol == "-->")
        }
        return nil
    }

    /// Splits a trailing " : 4" weight off an edge line.
    private static func splitWeight(_ line: String) -> (String, String?) {
        guard let colon = line.range(of: ":", options: .backwards) else { return (line, nil) }
        let weight = line[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        let body = line[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
        guard !weight.isEmpty, !body.isEmpty, weight.count <= 12, !weight.contains("\"") else { return (line, nil) }
        return (body, weight)
    }

    /// UTF-16 ranges of "double-quoted" spans, so operators inside names are ignored.
    private static func quotedRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?
        for (offset, unit) in text.utf16.enumerated() where unit == 0x22 {
            if let open = start {
                ranges.append(NSRange(location: open, length: offset - open + 1))
                start = nil
            } else {
                start = offset
            }
        }
        return ranges
    }

    private static func looksLikeCourseCode(_ left: String, _ right: String) -> Bool {
        left.count <= 5 && left.allSatisfy(\.isLetter) && right.first?.isNumber == true
    }

    // MARK: - Highlight parsing

    /// Reads "A -> B -> D" (path: nodes plus edges), "A, B, C" (nodes only),
    /// or legacy "A B D" / "A-B-D" (path).
    private static func parseHighlight(_ spec: String, known: Set<String>) -> Highlight {
        let body = spec.trimmingCharacters(in: .whitespaces)
        var result = Highlight()

        func addPath(_ names: [String]) {
            let valid = names.filter { known.contains($0) }
            for name in valid where !result.nodes.contains(name) { result.nodes.append(name) }
            for pair in zip(valid, valid.dropFirst()) { result.pairs.insert(NodePair(pair.0, pair.1)) }
        }

        let range = NSRange(body.startIndex..., in: body)
        if spacedOperator.firstMatch(in: body, range: range) != nil {
            for segment in body.split(separator: ",") {
                let s = String(segment)
                let names = spacedOperator
                    .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\u{1F}")
                    .split(separator: "\u{1F}")
                    .map { unquote(String($0)) }
                addPath(names)
            }
            return result
        }

        if body.contains(",") {
            for name in body.split(separator: ",").map({ unquote(String($0)) }) where known.contains(name) {
                if !result.nodes.contains(name) { result.nodes.append(name) }
            }
            return result
        }

        if known.contains(unquote(body)) {
            addPath([unquote(body)])
            return result
        }
        for symbol in ["->", ">", "--", "-"] where body.contains(symbol) {
            let names = body.components(separatedBy: symbol).map { unquote($0) }
            if names.allSatisfy(known.contains) {
                addPath(names)
                return result
            }
        }
        addPath(greedyNames(body.split(separator: " ").map(String.init), known: known))
        return result
    }

    /// Joins whitespace tokens into the longest known node names, so
    /// "highlight: CS 1114 CS 2114" finds the nodes "CS 1114" and "CS 2114".
    private static func greedyNames(_ tokens: [String], known: Set<String>) -> [String] {
        var names: [String] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            for length in stride(from: min(4, tokens.count - index), through: 1, by: -1) {
                let candidate = unquote(tokens[index..<(index + length)].joined(separator: " "))
                if known.contains(candidate) {
                    names.append(candidate)
                    index += length
                    matched = true
                    break
                }
            }
            if !matched { index += 1 }
        }
        return names
    }

    // MARK: - Helpers

    private static func directive(_ name: String, in line: String) -> String? {
        let prefix = name + ":"
        guard line.lowercased().hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    /// "graph TD" / "flowchart LR" headers that models carry over from Mermaid.
    private static func isMermaidHeader(_ line: String) -> Bool {
        line.range(of: #"^(graph|flowchart)(\s+(TD|TB|LR|RL|BT))?;?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func stripComment(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return "" }
        if let range = line.range(of: " # ") { return String(line[..<range.lowerBound]) }
        return line
    }

    private static func unquote(_ value: String) -> String {
        var name = value.trimmingCharacters(in: .whitespaces)
        if name.count >= 2, let first = name.first, let last = name.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            name = String(name.dropFirst().dropLast())
        }
        return name
    }
}

// MARK: - Layout

private nonisolated enum Layout {
    struct Result {
        let positions: [String: CGPoint]
        let isTree: Bool
        let layerCount: Int
    }

    static func compute(nodes: [String], edges: [SimpleGraph.Edge], isDirected: Bool) -> Result {
        if nodes.count == 1 {
            return Result(positions: [nodes[0]: CGPoint(x: 0.5, y: 0.5)], isTree: false, layerCount: 1)
        }
        if let tree = treeLayout(nodes: nodes, edges: edges, isDirected: isDirected) {
            return tree
        }
        return Result(positions: forceLayout(nodes: nodes, edges: edges), isTree: false, layerCount: 0)
    }

    /// Layered layout for connected acyclic graphs: root on top, children
    /// below, each parent centered over its leaves.
    private static func treeLayout(nodes: [String], edges: [SimpleGraph.Edge], isDirected: Bool) -> Result? {
        let pairs = Set(edges.map { SimpleGraph.NodePair($0.from, $0.to) })
        guard pairs.count == nodes.count - 1, pairs.allSatisfy({ $0.a != $0.b }) else { return nil }

        var neighbors: [String: [String]] = [:]
        var inDegree: [String: Int] = [:]
        for edge in edges {
            neighbors[edge.from, default: []].append(edge.to)
            neighbors[edge.to, default: []].append(edge.from)
            if edge.directed { inDegree[edge.to, default: 0] += 1 }
        }
        let root = isDirected ? (nodes.first { inDegree[$0, default: 0] == 0 } ?? nodes[0]) : nodes[0]

        var children: [String: [String]] = [:]
        var depth: [String: Int] = [root: 0]
        var queue = [root]
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for next in neighbors[node, default: []] where depth[next] == nil {
                depth[next] = depth[node, default: 0] + 1
                children[node, default: []].append(next)
                queue.append(next)
            }
        }
        guard queue.count == nodes.count else { return nil }

        var slot: [String: Double] = [:]
        var nextLeaf = 0.0
        func place(_ node: String) {
            let kids = children[node, default: []]
            if kids.isEmpty {
                slot[node] = nextLeaf
                nextLeaf += 1
                return
            }
            kids.forEach(place)
            let xs = kids.compactMap { slot[$0] }
            slot[node] = (xs.min()! + xs.max()!) / 2
        }
        place(root)

        let maxDepth = depth.values.max() ?? 0
        let leafSpan = max(nextLeaf - 1, 1)
        var positions: [String: CGPoint] = [:]
        for node in nodes {
            let x = nextLeaf <= 1 ? 0.5 : (slot[node] ?? 0) / leafSpan
            let y = maxDepth == 0 ? 0.5 : Double(depth[node] ?? 0) / Double(maxDepth)
            positions[node] = CGPoint(x: x, y: y)
        }
        return Result(positions: positions, isTree: true, layerCount: maxDepth + 1)
    }

    /// Deterministic Fruchterman–Reingold layout seeded from a circle.
    private static func forceLayout(nodes: [String], edges: [SimpleGraph.Edge]) -> [String: CGPoint] {
        let count = nodes.count
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1, $0) })
        var x = (0..<count).map { 0.5 + 0.4 * cos(Double($0) / Double(count) * 2 * .pi - .pi / 2) }
        var y = (0..<count).map { 0.5 + 0.4 * sin(Double($0) / Double(count) * 2 * .pi - .pi / 2) }
        let links = edges.compactMap { edge -> (Int, Int)? in
            guard let a = index[edge.from], let b = index[edge.to], a != b else { return nil }
            return (a, b)
        }

        let k = sqrt(1.0 / Double(count))
        let iterations = 300
        for iteration in 0..<iterations {
            var dx = [Double](repeating: 0, count: count)
            var dy = [Double](repeating: 0, count: count)
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let ddx = x[i] - x[j]
                    let ddy = y[i] - y[j]
                    let distance = max(sqrt(ddx * ddx + ddy * ddy), 0.01)
                    let force = k * k / distance
                    dx[i] += ddx / distance * force
                    dy[i] += ddy / distance * force
                    dx[j] -= ddx / distance * force
                    dy[j] -= ddy / distance * force
                }
            }
            for (a, b) in links {
                let ddx = x[a] - x[b]
                let ddy = y[a] - y[b]
                let distance = max(sqrt(ddx * ddx + ddy * ddy), 0.01)
                let force = distance * distance / k
                dx[a] -= ddx / distance * force
                dy[a] -= ddy / distance * force
                dx[b] += ddx / distance * force
                dy[b] += ddy / distance * force
            }
            let temperature = 0.1 * (1 - Double(iteration) / Double(iterations)) + 0.002
            for i in 0..<count {
                let length = max(sqrt(dx[i] * dx[i] + dy[i] * dy[i]), 0.0001)
                x[i] += dx[i] / length * min(length, temperature)
                y[i] += dy[i] / length * min(length, temperature)
            }
        }

        // Normalize into the unit square, keeping the aspect of the layout.
        let minX = x.min()!, maxX = x.max()!, minY = y.min()!, maxY = y.max()!
        let spanX = max(maxX - minX, 0.0001), spanY = max(maxY - minY, 0.0001)
        var positions: [String: CGPoint] = [:]
        for (i, node) in nodes.enumerated() {
            positions[node] = CGPoint(
                x: spanX < 0.01 ? 0.5 : (x[i] - minX) / spanX,
                y: spanY < 0.01 ? 0.5 : (y[i] - minY) / spanY
            )
        }
        return positions
    }
}
