<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('upload_max_filesize', '10M');
ini_set('post_max_size', '10M');

$envFile = __DIR__ . '/../.env';
if (file_exists($envFile)) {
    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        if (strpos($line, '=') !== false) {
            list($key, $value) = explode('=', $line, 2);
            $_ENV[trim($key)] = trim($value, " \t\n\r\0\x0B\"'");
        }
    }
}

define('DB_HOST', $_ENV['DB_HOST'] ?? 'localhost');
define('DB_NAME', $_ENV['DB_NAME'] ?? 'seederlinux');
define('DB_USER', $_ENV['DB_USER'] ?? 'seeder');
define('DB_PASS', $_ENV['DB_PASS'] ?? 'seeder123');
define('DB_PORT', $_ENV['DB_PORT'] ?? 5432);
date_default_timezone_set('America/Sao_Paulo');
