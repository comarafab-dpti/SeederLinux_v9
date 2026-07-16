<?php
class Database {
    private static $pdo = null;

    private static function connect() {
        if (self::$pdo !== null) return self::$pdo;
        $dsn = sprintf('pgsql:host=%s;port=%s;dbname=%s', DB_HOST, DB_PORT, DB_NAME);
        self::$pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        return self::$pdo;
    }

    public static function fetchOne($sql, $params = []) {
        $stmt = self::connect()->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetch();
    }

    public static function fetchAll($sql, $params = []) {
        $stmt = self::connect()->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public static function execute($sql, $params = []) {
        $stmt = self::connect()->prepare($sql);
        return $stmt->execute($params);
    }

    public static function lastInsertId() {
        return self::connect()->lastInsertId();
    }

    public static function beginTransaction() { return self::connect()->beginTransaction(); }
    public static function commit() { return self::connect()->commit(); }
    public static function rollback() { return self::connect()->rollback(); }
}
