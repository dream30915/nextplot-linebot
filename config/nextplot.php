<?php

/**
 * NextPlot Configuration
 *
 * คัดลอกไฟล์นี้ไปที่: config/nextplot.php
 * จากนั้นตั้งค่าใน .env:
 *
 * LINE_CHANNEL_ACCESS_TOKEN=your_channel_access_token
 * LINE_CHANNEL_SECRET=your_channel_secret
 * LINE_USER_ID_ALLOWLIST=Ub58d192d370a1427a3c2eabc82f2d16b
 * LINE_SIGNATURE_RELAXED=false
 *
 * SUPABASE_URL=https://xhcogxcmljnczwybqvia.supabase.co
 * SUPABASE_ANON_KEY=your_anon_key
 * SUPABASE_SERVICE_ROLE=your_service_role_key
 * SUPABASE_BUCKET_NAME=nextplot
 */

return [

    /*
    |--------------------------------------------------------------------------
    | LINE Messaging API Configuration
    |--------------------------------------------------------------------------
    */

    'line' => [
        'access_token'      => env('LINE_CHANNEL_ACCESS_TOKEN'),
        'channel_secret'    => env('LINE_CHANNEL_SECRET'),
        'user_id_allowlist' => env('LINE_USER_ID_ALLOWLIST', ''),
        'signature_relaxed' => env('LINE_SIGNATURE_RELAXED', false),
    ],

    /*
    |--------------------------------------------------------------------------
    | Supabase Configuration
    |--------------------------------------------------------------------------
    */

    'supabase' => [
        'url'          => env('SUPABASE_URL'),
        'anon_key'     => env('SUPABASE_ANON_KEY'),
        'service_role' => env('SUPABASE_SERVICE_ROLE'),
        'bucket_name'  => env('SUPABASE_BUCKET_NAME', 'nextplot'),
    ],

    /*
    |--------------------------------------------------------------------------
    | NextPlot Features
    |--------------------------------------------------------------------------
    */

    'features' => [
        'quick_reply'     => true,
        'media_upload'    => true,
        'signed_urls'     => true,
        'session_timeout' => 600, // 10 minutes in seconds
    ],

    /*
    |--------------------------------------------------------------------------
    | Bot Tone (Formal/Friendly)
    |--------------------------------------------------------------------------
    | กำหนดโทนภาษาในการตอบกลับของบอท
    | - formal: สุภาพ ทางการ อธิบายเชิงขั้นตอน
    | - friendly: กันเอง มีอีโมจิเล็กน้อย
    */
    'bot' => [
        'tone' => env('NEXTPLOT_BOT_TONE', 'formal'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Conversational AI Settings
    |--------------------------------------------------------------------------
    | เปิด/ปิด และตั้งค่าการสนทนาแบบ AI
    | driver: none|openai (รองรับ OpenAI API มาตรฐาน)
    */
    'chat' => [
        // Auto-enable when OPENAI_API_KEY is present unless explicitly disabled
        'enabled'       => env('NEXTPLOT_CHAT_ENABLED', env('OPENAI_API_KEY') ? true : false),
        'driver'        => env('NEXTPLOT_CHAT_DRIVER', 'none'),
        // OpenAI settings
        'openai' => [
            'api_key'      => env('OPENAI_API_KEY'),
            'base_url'     => env('OPENAI_BASE_URL', 'https://api.openai.com/v1'),
            'model'        => env('OPENAI_CHAT_MODEL', 'gpt-4o-mini'),
            'temperature'  => env('OPENAI_TEMPERATURE', 0.3),
            'max_tokens'   => env('OPENAI_MAX_TOKENS', 300),
            'system_prompt' => env('OPENAI_SYSTEM_PROMPT', 'คุณคือผู้ช่วยสำหรับงาน NextPlot โปรดตอบเป็นภาษาไทยที่สุภาพ ชัดเจน และให้คำแนะนำเป็นขั้นตอนเมื่อเหมาะสม'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Conversation Logging
    |--------------------------------------------------------------------------
    | Log only meaningful records (finalized text with CODE+โฉนด and saved media).
    | File stored in storage/app by default.
    */
    'logging' => [
        'enabled' => env('NEXTPLOT_LOG_ENABLED', true),
        'file'    => env('NEXTPLOT_LOG_FILE', 'conversations.ndjson'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Conversation Context (Memory)
    |--------------------------------------------------------------------------
    | Driver options:
    | - file: store per-user/group state in local storage (storage/app/user_state)
    | - supabase: store state in Supabase table (see 'context.table')
    */
    'context' => [
        'driver' => env('NEXTPLOT_CONTEXT_DRIVER', 'file'),
        'table'  => env('NEXTPLOT_CONTEXT_TABLE', 'user_states'),
        // Scope of memory key: 'chat' (per group/room) or 'user' (per user across chats)
        'scope'  => env('NEXTPLOT_CONTEXT_SCOPE', 'chat'),
    ],

];
