<?php

namespace App\Http\Middleware;

use Illuminate\Foundation\Http\Middleware\VerifyCsrfToken as Middleware;

class VerifyCsrfToken extends Middleware
{
    // ไม่จำเป็นสำหรับวิธีนี้ (เราใช้กลุ่ม API) แต่กันพลาดเผื่อมีการเรียกผ่าน /line/webhook ตรง
    protected $except = [
        '/line/webhook',
        '/line/webhook/*',
    ];
}
