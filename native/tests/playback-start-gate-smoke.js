'use strict';
// Source contracts for the startup barrier. Device tests must additionally
// observe a current-load frame before the audio-release marker.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const read = name => fs.readFileSync(path.join(__dirname, '../src', name), 'utf8');
const player = read('mpvvideoitem.cpp');
const decoder = read('droidvideodecoder.cpp');
assert(player.includes('m_initialPositionGatePending = videoEnabled;'));
assert(!player.includes('m_initialPositionGatePending = startPosition > 0.0;'));
assert(player.includes('m_seekPending = startPosition > 0.0;'));
assert(player.includes('if (m_initialPositionGatePending || m_pendingLoadPause)'));
assert(player.includes('else if (m_initialPositionGatePending) {'));
assert(player.includes('enableSourceFramePresentation("initial-zero-start-confirmed")'));
assert(player.includes('!m_initialVideoFrameReady || !m_backend || m_backend->loadPending'));
assert(player.includes('if (m_initialPositionGatePending) paused = m_requestedPaused;'));
const loop = decoder.slice(decoder.indexOf('void DroidVideoDecoder::presentLoop('));
assert(loop.indexOf('frame.ptsUs < m_dropBeforeUs.load()') < loop.indexOf('primedSeekSerial != seekSerial'));
assert(loop.indexOf('primedSeekSerial != seekSerial') < loop.indexOf('masterClockUs(&clockValid)'));
assert(loop.includes('audioClockWait" << false'));
// The gate requires three independent conditions, irrespective of start time.
for (const position of [0, 14, 90]) {
    for (const loaded of [false, true]) {
        for (const targetConfirmed of [false, true]) {
            for (const frameReady of [false, true]) {
                const release = loaded && targetConfirmed && frameReady;
                for (const userPaused of [false, true]) {
                    const audioRuns = release && !userPaused;
                    if (!loaded || !targetConfirmed || !frameReady || userPaused)
                        assert.equal(audioRuns, false, `unsafe audio start at ${position}`);
                }
            }
        }
    }
}
console.log('playback_start_gate=ready|source_contracts=passed|state_combinations=48|device_validation=required');
