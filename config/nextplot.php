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
    | Conversation Logging
    |--------------------------------------------------------------------------
    | Log only meaningful records (finalized text with CODE+โฉนด and saved media).
    | File stored in storage/app by default.
    */
    'logging' => [
        'enabled' => env('NEXTPLOT_LOG_ENABLED', true),
        'file'    => env('NEXTPLOT_LOG_FILE', 'conversations.ndjson'),
    ],

];
