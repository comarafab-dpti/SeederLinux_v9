<?php
/**
 * Teste de validacao MIME real com finfo_file()
 * Uso: php /app/tests/test_upload_mime.php
 */

$tmpDir = sys_get_temp_dir();
$fail = 0;

// Test 1: .txt renamed to .png must be rejected
$fake = $tmpDir . '/fake.png';
file_put_contents($fake, "This is plain text pretending to be a PNG\n");
$finfo = finfo_open(FILEINFO_MIME_TYPE);
$real = finfo_file($finfo, $fake);
finfo_close($finfo);
$allowed = ["image/jpeg","image/png","image/gif","image/webp"];
if ($real === "text/plain" && !in_array($real, $allowed, true)) {
    echo "[OK] fake.png rejected (real MIME: $real)\n";
} else {
    echo "[FAIL] fake.png not rejected (got: $real)\n"; $fail = 1;
}
unlink($fake);

// Test 2: real PNG must pass
$realPng = $tmpDir . '/real.png';
file_put_contents($realPng, base64_decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
));
$finfo = finfo_open(FILEINFO_MIME_TYPE);
$real = finfo_file($finfo, $realPng);
finfo_close($finfo);
if ($real === "image/png" && in_array($real, $allowed, true)) {
    echo "[OK] real.png accepted (real MIME: $real)\n";
} else {
    echo "[FAIL] real.png not accepted (got: $real)\n"; $fail = 1;
}
unlink($realPng);

// Test 3: SVG normalization (image/svg -> image/svg+xml)
$svg = $tmpDir . '/logo.svg';
file_put_contents($svg, '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>');
$finfo = finfo_open(FILEINFO_MIME_TYPE);
$real = finfo_file($finfo, $svg);
finfo_close($finfo);
// Simula normalizacao usada no backend
if (in_array($real, ['image/svg', 'text/xml', 'application/xml'], true)) {
    $real = 'image/svg+xml';
}
$logoAllowed = array_merge($allowed, ['image/svg+xml']);
if (in_array($real, $logoAllowed, true)) {
    echo "[OK] logo.svg accepted after normalization (final MIME: $real)\n";
} else {
    echo "[FAIL] logo.svg rejected (got: $real)\n"; $fail = 1;
}
unlink($svg);

exit($fail);
