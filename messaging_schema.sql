-- Eventzone App - Messaging Schema Migration SQL (Flexible Version)
-- Run this in your Supabase SQL Editor to set up/reset the messages table.
-- This version removes strict foreign key constraints to allow messaging both registered profiles and scanned connections.

-- 1. Drop existing messages table if it exists to clean constraints
DROP TABLE IF EXISTS public.messages CASCADE;

-- 2. Create the flexible public.messages table
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL,
    recipient_id UUID NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    is_read BOOLEAN DEFAULT false NOT NULL
);

-- 3. Disable Row Level Security (RLS) for testing/development (ensures inserts/selects work without Auth session)
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;

-- 4. Create performance indexes for chat queries
CREATE INDEX IF NOT EXISTS idx_messages_sender_recipient ON public.messages(sender_id, recipient_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);

-- 5. Add messages to real-time publication to enable instant UI streaming updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
