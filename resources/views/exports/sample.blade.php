<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <title>{{ $title ?? 'Export' }}</title>
    <style>
        body { font-family: DejaVu Sans, sans-serif; font-size: 12px; }
        h1 { font-size: 18px; margin-bottom: 8px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #999; padding: 6px; text-align: left; }
        th { background: #f2f2f2; }
        .meta { margin-bottom: 10px; color: #666; }
    </style>
</head>
<body>
    <h1>{{ $title ?? 'Export' }}</h1>
    <div class="meta">สร้างเมื่อ: {{ $generated_at ?? '' }}</div>

    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Code</th>
                <th>Session</th>
                <th>Message</th>
                <th>Created At</th>
            </tr>
        </thead>
        <tbody>
            @foreach(($rows ?? []) as $r)
                <tr>
                    <td>{{ $r['id'] }}</td>
                    <td>{{ $r['code'] }}</td>
                    <td>{{ $r['session'] }}</td>
                    <td>{{ $r['message'] }}</td>
                    <td>{{ $r['created_at'] }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>
</body>
</html>
