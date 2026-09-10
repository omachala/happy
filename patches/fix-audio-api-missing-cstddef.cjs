/**
 * Patches react-native-audio-api (0.8.4) to include <cstddef> in
 * audioapi/core/Constants.h.
 *
 * The header declares `static constexpr size_t MAX_FFT_SIZE` but only includes
 * <cmath> and <limits>. Older clang happened to pull `size_t` in transitively
 * through those; the clang shipped in Xcode 26.6 does not, so every translation
 * unit that includes Constants.h fails with:
 *
 *   error: unknown type name 'size_t'; did you mean 'std::size_t'?
 *
 * which breaks the Release archive in RNAudioAPI (Windows.cpp, VectorMath.cpp,
 * and friends). Upstream bug; drop this patch once react-native-audio-api ships
 * the include itself.
 */
const fs = require('fs');
const path = require('path');

let patched = 0;

const nodeModulesRoots = [
    path.resolve(__dirname, '..', 'node_modules'),
    path.resolve(__dirname, '..', 'packages/happy-app/node_modules'),
];

for (const nodeModulesRoot of nodeModulesRoots) {
    const filePath = path.join(
        nodeModulesRoot,
        'react-native-audio-api/common/cpp/audioapi/core/Constants.h'
    );
    if (!fs.existsSync(filePath)) continue;

    let content = fs.readFileSync(filePath, 'utf8');
    // Idempotent: only add the include if it isn't already there.
    if (content.includes('#include <cstddef>')) continue;

    const original = content;
    content = content.replace(
        '#include <cmath>',
        '#include <cmath>\n#include <cstddef>'
    );
    if (content !== original) {
        fs.writeFileSync(filePath, content, 'utf8');
        patched++;
    }
}

if (patched > 0) {
    console.log(`[patch] Added missing <cstddef> to react-native-audio-api Constants.h (${patched} file(s))`);
}
