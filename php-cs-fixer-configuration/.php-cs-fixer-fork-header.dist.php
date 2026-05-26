<?php

return static function (\PhpCsFixer\Finder $finder, string $upstreamCopyright): string {
    $headerLicense = PHP_EOL . '@license    https://www.gnu.org/licenses/gpl-3.0.html  GNU General Public License version 3 (GPLv3)';

    $headerBase = 'OpenDXP' . PHP_EOL
        . PHP_EOL
        . 'This source file is licensed under the GNU General Public License version 3 (GPLv3).' . PHP_EOL
        . PHP_EOL
        . 'Full copyright and license information is available in' . PHP_EOL
        . 'LICENSE.md which is distributed with this source code.' . PHP_EOL
        . PHP_EOL;

    $headerForked = $headerBase
        . $upstreamCopyright . PHP_EOL
        . '@copyright  Modification Copyright (c) OpenDXP (https://www.opendxp.io)'
        . $headerLicense;

    $headerNew = $headerBase
        . '@copyright  Copyright (c) OpenDXP (https://www.opendxp.io)'
        . $headerLicense;

    $forkPoint = getenv('FORK_POINT') ?: '';
    $mode = getenv('CS_FIXER_MODE') ?: '';

    if ($forkPoint === '' || $mode === '') {
        return $headerForked;
    }

    $cmd = sprintf('git log --diff-filter=A --name-only --pretty=format: %s..HEAD', escapeshellarg($forkPoint));
    exec($cmd, $output);

    $newFiles = [];
    foreach ($output as $path) {

        $path = trim($path);
        if ($path === '' || !str_ends_with($path, '.php')) {
            continue;
        }

        $real = realpath($path);
        if ($real !== false) {
            $newFiles[$real] = true;
        }
    }

    $isNew = $mode === 'new';
    $finder->filter(fn(\SplFileInfo $f) => isset($newFiles[$f->getRealPath()]) === $isNew);

    return $isNew ? $headerNew : $headerForked;
};