<?php
/**
 * SeederLinux Lite - Session Diagnostic Tool
 * Access via: https://seederlinux.comara.intraer/test_session.php
 * Delete after debugging!
 */

session_start();
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Credentials: true');

// Detect HTTPS
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (($_SERVER['SERVER_PORT'] ?? '') == 443)
    || (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https');

// Show session configuration
echo json_encode([
    'session_id' => session_id(),
    'session_name' => session_name(),
    'session_data' => $_SESSION,
    'cookies' => $_COOKIE,
    'server' => [
        'HTTPS' => $_SERVER['HTTPS'] ?? 'not set',
        'SERVER_PORT' => $_SERVER['SERVER_PORT'] ?? 'not set',
        'HTTP_HOST' => $_SERVER['HTTP_HOST'] ?? 'not set',
        'REQUEST_URI' => $_SERVER['REQUEST_URI'] ?? 'not set',
        'HTTP_COOKIE' => $_SERVER['HTTP_COOKIE'] ?? 'not set',
    ],
    'php_config' => [
        'session.save_path' => ini_get('session.save_path'),
        'session.cookie_path' => ini_get('session.cookie_path'),
        'session.cookie_domain' => ini_get('session.cookie_domain'),
        'session.cookie_secure' => ini_get('session.cookie_secure'),
        'session.cookie_httponly' => ini_get('session.cookie_httponly'),
        'session.cookie_samesite' => ini_get('session.cookie_samesite'),
        'session.use_strict_mode' => ini_get('session.use_strict_mode'),
    ],
    'https_detected' => $isHttps,
], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
