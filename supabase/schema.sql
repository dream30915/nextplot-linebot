-- NextPlot Database Schema for Supabase
-- Version: 1.0.0
-- Last Updated: 2025-10-19

-- =====================================================
-- Table: members
-- ข้อมูลสมาชิก/ผู้ใช้ที่ได้รับอนุญาต
-- =====================================================
CREATE TABLE IF NOT EXISTS public.members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- LINE profile
    line_user_id TEXT NOT NULL UNIQUE,
    display_name TEXT,
    picture_url TEXT,
    
    -- Roles & Permissions
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('owner', 'editor', 'viewer')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    
    -- Contact info
    phone TEXT,
    email TEXT,
    
    -- Metadata
    last_active_at TIMESTAMPTZ,
    notes TEXT
);

CREATE INDEX idx_members_line_user_id ON public.members(line_user_id);
CREATE INDEX idx_members_role ON public.members(role);

-- =====================================================
-- Table: properties
-- ข้อมูลแปลงที่ดิน
-- =====================================================
CREATE TABLE IF NOT EXISTS public.properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finalized_at TIMESTAMPTZ,
    
    -- Property Code (e.g., WC-007)
    code TEXT NOT NULL,
    run_number INTEGER,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending', 'finalized', 'archived')),
    
    -- Deed Information
    deed_number TEXT,
    deed_type TEXT, -- โฉนด, น.ส.3, น.ส.3ก, etc.
    plots_count_declared INTEGER, -- จำนวนแปลงที่ประกาศ (e.g., "โฉนด 5 แปลง")
    
    -- Area (เนื้อที่)
    area_rai NUMERIC(10,2),
    area_ngan NUMERIC(10,2),
    area_wa NUMERIC(10,2),
    area_sqm NUMERIC(15,2), -- ตารางเมตรรวม
    
    -- Price
    price_per_wa NUMERIC(15,2),
    price_total NUMERIC(15,2),
    
    -- Owner/Referrer
    owner_name TEXT,
    referred_by UUID REFERENCES public.members(id),
    
    -- Location
    province TEXT,
    district TEXT,
    subdistrict TEXT,
    
    -- Coordinates
    latitude NUMERIC(10,7),
    longitude NUMERIC(10,7),
    
    -- Summary
    description TEXT,
    notes TEXT,
    
    -- Session tracking (จัดกลุ่ม messages ตาม session)
    session_id TEXT,
    
    -- Metadata
    created_by UUID REFERENCES public.members(id),
    
    UNIQUE(code, run_number)
);

CREATE INDEX idx_properties_code ON public.properties(code);
CREATE INDEX idx_properties_status ON public.properties(status);
CREATE INDEX idx_properties_session_id ON public.properties(session_id);
CREATE INDEX idx_properties_deed_number ON public.properties(deed_number);

-- =====================================================
-- Table: deed_addresses
-- ที่อยู่โฉนด (แยกตารางเพื่อรองรับหลายแปลงที่มีที่อยู่เดียวกัน)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.deed_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    
    -- Address components
    address_line1 TEXT,
    address_line2 TEXT,
    subdistrict TEXT,
    district TEXT,
    province TEXT,
    postal_code TEXT,
    
    -- Full address
    full_address TEXT
);

CREATE INDEX idx_deed_addresses_property_id ON public.deed_addresses(property_id);

-- =====================================================
-- Table: events
-- เหตุการณ์ทั้งหมด (Audit log)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    event_type TEXT NOT NULL CHECK (event_type IN (
        'property_created',
        'property_updated',
        'property_finalized',
        'property_archived',
        'export_requested',
        'export_completed',
        'message_received',
        'media_uploaded',
        'user_logged_in'
    )),
    
    -- References
    user_id UUID REFERENCES public.members(id),
    property_id UUID REFERENCES public.properties(id),
    
    -- Event data
    data JSONB,
    
    -- IP and metadata
    ip_address TEXT,
    user_agent TEXT
);

CREATE INDEX idx_events_event_type ON public.events(event_type);
CREATE INDEX idx_events_user_id ON public.events(user_id);
CREATE INDEX idx_events_property_id ON public.events(property_id);
CREATE INDEX idx_events_created_at ON public.events(created_at DESC);

-- =====================================================
-- Enable Row Level Security (RLS)
-- =====================================================
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deed_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- RLS Policies (Owner-only mode)
-- ให้ service_role มีสิทธิ์เต็ม
CREATE POLICY "Service role has full access" ON public.members
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Service role has full access" ON public.properties
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Service role has full access" ON public.deed_addresses
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Service role has full access" ON public.events
    FOR ALL USING (auth.role() = 'service_role');

-- =====================================================
-- Functions & Triggers
-- =====================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for auto-updating updated_at
CREATE TRIGGER update_members_updated_at
    BEFORE UPDATE ON public.members
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_properties_updated_at
    BEFORE UPDATE ON public.properties
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_deed_addresses_updated_at
    BEFORE UPDATE ON public.deed_addresses
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- Sample Data (for testing)
-- =====================================================

-- Insert allowlist member
INSERT INTO public.members (line_user_id, display_name, role, is_active)
VALUES ('Ub58d192d370a1427a3c2eabc82f2d16b', 'Owner', 'owner', true)
ON CONFLICT (line_user_id) DO NOTHING;

-- =====================================================
-- Views (Optional)
-- =====================================================

-- View: Property summary with member info
CREATE OR REPLACE VIEW public.properties_summary AS
SELECT 
    p.id,
    p.code,
    p.run_number,
    p.status,
    p.deed_number,
    p.area_rai,
    p.area_ngan,
    p.area_wa,
    p.price_total,
    p.province,
    p.district,
    m.display_name AS created_by_name,
    r.display_name AS referred_by_name,
    p.created_at,
    p.finalized_at
FROM public.properties p
LEFT JOIN public.members m ON p.created_by = m.id
LEFT JOIN public.members r ON p.referred_by = r.id;

-- =====================================================
-- Storage Bucket Setup
-- =====================================================
-- Note: ต้องสร้าง bucket ผ่าน Supabase Dashboard หรือ API
-- Bucket name: 'nextplot'
-- Public: false
-- File size limit: 50MB
-- Allowed MIME types: image/*, application/pdf, application/msword, etc.

-- =====================================================
-- Indexes for Performance
-- =====================================================

-- Full-text search on properties
CREATE INDEX idx_properties_search ON public.properties 
USING GIN (to_tsvector('thai', COALESCE(description, '') || ' ' || COALESCE(notes, '')));

-- GIS index (ถ้าต้องการค้นหาตามพิกัด)
-- CREATE INDEX idx_properties_location ON public.properties 
-- USING GIST (ST_MakePoint(longitude, latitude));

COMMENT ON TABLE public.members IS 'ข้อมูลสมาชิกที่ได้รับอนุญาต';
COMMENT ON TABLE public.properties IS 'ข้อมูลแปลงที่ดิน';
COMMENT ON TABLE public.deed_addresses IS 'ที่อยู่โฉนด';
COMMENT ON TABLE public.events IS 'Audit log สำหรับทุกเหตุการณ์';
