<?php
/**
 * SeederLinux Lite - Download Handler
 * Serves files from the downloads directory
 */

declare(strict_types=1);

// Allowed files for download
$allowedFiles = [
    'agent.py' => __DIR__ . '/../downloads/agent.py',
    'DOCUMENTACAO.md' => __DIR__ . '/../downloads/DOCUMENTACAO.md',
];

// Get requested file
$file = $_GET['file'] ?? '';

if (!isset($allowedFiles[$file])) {
    http_response_code(404);
    exit('Arquivo não encontrado');
}

$filePath = $allowedFiles[$file];

if (!file_exists($filePath)) {
    http_response_code(404);
    exit('Arquivo não encontrado');
}

// Set appropriate headers
$mimeType = 'application/octet-stream';
if (str_ends_with($file, '.py')) {
    $mimeType = 'text/x-python';
} elseif (str_ends_with($file, '.md')) {
    $mimeType = 'text/markdown';
}
if (str_ends_with($file, '.sh')) {
    $mimeType = 'application/x-sh';
}

header('Content-Type: ' . $mimeType);
header('Content-Disposition: attachment; filename="' . basename($file) . '"');
header('Content-Length: ' . filesize($filePath));
header('Cache-Control: no-cache, must-revalidate');
header('Pragma: public');

// Output file content
readfile($filePath);
exit;
