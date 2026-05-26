<?php

$rulesFile = __DIR__ . '/.php-cs-fixer-rules-global.php';
$finderFile = __DIR__ . '/.php-cs-fixer-finder.dist.php';
$forkHeaderFile = __DIR__ . '/.php-cs-fixer-fork-header-global.php';

if (!file_exists($finderFile)) {
    throw new RuntimeException('Finder file not found: ' . $finderFile);
}

$finder = require $finderFile;
$rules = require $rulesFile;
$forkHeader = require $forkHeaderFile;

$rules['header_comment'] = [
    'comment_type' => 'PHPDoc',
    'header'       => $forkHeader($finder, '@copyright  Copyright (c) Pimcore GmbH (https://pimcore.com)'),
];

$config = new PhpCsFixer\Config();
$config->setRules($rules);
$config->setFinder($finder);

return $config;