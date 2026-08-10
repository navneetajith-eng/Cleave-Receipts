-- Application data is served by the authenticated backend, not Supabase Data API.
-- Keep the public schema for SQLAlchemy while denying direct anon/authenticated access.

REVOKE ALL PRIVILEGES ON TABLE
    public.users,
    public.profiles,
    public.groups,
    public.group_members,
    public.receipts,
    public.receipt_items,
    public.receipt_assignments,
    public.line_items,
    public.line_item_assignments,
    public.settlements,
    public.receipt_memories,
    public.receipt_experiences,
    public.inbox_items
FROM anon, authenticated;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.line_item_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_experiences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inbox_items ENABLE ROW LEVEL SECURITY;

-- Inbox operations also go through the backend. Remove the older direct-client policies
-- so an accidental future table grant cannot bypass backend authorization checks.
DROP POLICY IF EXISTS "Users can read their inbox" ON public.inbox_items;
DROP POLICY IF EXISTS "Users can update their inbox" ON public.inbox_items;

-- This function is invoked by the auth.users trigger. Clients never need to call it.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- service_role and default privileges are intentionally unchanged in this first,
-- staged hardening pass. They can be tightened after production smoke testing.
