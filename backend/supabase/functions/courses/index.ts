// Edge function: course companion (registration guidance, private syllabi,
// review, and current-course dashboards). POST /courses with {"action": ...}.
//
// Data access uses the student's own token, so row-level security and storage
// policies decide what each request can read or change.

import { requireUser } from "../_shared/auth.ts";
import { handleHTTP } from "./http.ts";
import { RestStore } from "./store_rest.ts";

Deno.serve((req) =>
  handleHTTP(req, {
    authenticate: async (req) => {
      const auth = await requireUser(req);
      if (auth.response) return auth.response;
      const token = (req.headers.get("authorization") ?? "").slice("bearer ".length).trim();
      return { userId: auth.user.id, token };
    },
    deps: ({ userId, token }) => ({
      store: new RestStore(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        token,
        userId,
      ),
      now: () => new Date(),
    }),
  })
);
