// Run with Node.js. Executes Home's real JavaScript policy functions with
// controlled QML state; source contracts below are not device performance tests.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function block(source, marker) {
    const start = source.indexOf(marker);
    assert(start >= 0, `Missing ${marker}`);
    const open = source.indexOf('{', start);
    let depth = 1, end = open + 1;
    while (depth && end < source.length) {
        if (source[end] === '{') ++depth;
        if (source[end] === '}') --depth;
        ++end;
    }
    assert.equal(depth, 0);
    return source.slice(open + 1, end - 1);
}
const home = read('qml/pages/HomePage.qml');
let prepared = 0, pageRequests = 0;
const state = {
    moving: false, dragging: false, width: 1080, height: 1800, contentY: 0,
    contentHeight: 6000, count: 30,
    page: {status: 1}, PageStatus: {Active: 1},
    Qt: {application: {active: true}},
    playbackSession: {active: false},
    homeFeed: {loading: false, hasMore: true, loadMore: () => ++pageRequests},
    nearBottom: () => true,
    itemAt: () => ({preparePlayback: () => ++prepared})
};
const context = vm.createContext(state);
const run = body => vm.runInContext(`(function() {${body}})()`, context);
const prepare = block(home, 'function prepareCenteredVideo()');
run(prepare);
assert.equal(prepared, 1, 'idle viewport should prefetch');
for (const [object, key, blockedValue] of [
    [state, 'moving', true], [state, 'dragging', true],
    [state.homeFeed, 'loading', true], [state.playbackSession, 'active', true],
    [state.page, 'status', 0], [state.Qt.application, 'active', false]
]) {
    const saved = object[key];
    object[key] = blockedValue;
    run(prepare);
    assert.equal(prepared, 1, `${key} must suppress speculative work`);
    object[key] = saved;
}
state.itemAt = () => null;
run(prepare); // Header/empty viewport must be harmless.
assert.equal(prepared, 1);
assert(!home.includes('onPressedChanged:'), 'press is not playback intent');
assert(!home.includes('Component.onCompleted:'), 'delegate creation must not prewarm');
assert(block(home, 'onMovementStarted:').includes('foregroundPrepareTimer.stop()'));
assert(block(home, 'onMovementEnded:').includes('foregroundPrepareTimer.restart()'));
assert(block(home, 'onTriggered:').includes('!listView.moving'));

const paginate = block(home, 'function maybeLoadMore()');
run(paginate);
assert.equal(pageRequests, 1);
state.homeFeed.loading = true;
for (let i = 0; i < 100; ++i) run(paginate);
assert.equal(pageRequests, 1, 'scroll notifications must not duplicate loading request');

const session = read('src/playbacksession.cpp');
const prepareSession = block(session, 'void PlaybackSession::prepareVideo(');
assert(prepareSession.includes('->prefetchVideo('));
assert(!prepareSession.includes('->resolve('));
assert(!prepareSession.includes('m_player'));
assert(!session.includes('m_prepar'), 'hidden decode state must be removed');
assert(!read('qml/pages/VideoDetailPage.qml').includes('onVideoPrepared'));
assert(!read('qml/main.qml').includes('deferAutoplayUntilPrefetched'));

const feed = read('src/homefeedmodel.cpp');
const failure = block(feed, 'if (parseError.error !=');
assert(failure.indexOf('setErrorMessage(') < failure.indexOf('setLoading(false)'));
for (const model of ['livefeedmodel', 'searchmodel']) {
    const body = read(`src/${model}.cpp`);
    const callback = body.slice(body.indexOf('connect(reply, &QNetworkReply::finished'));
    assert(callback.indexOf('setErrorMessage(') < callback.indexOf('setLoading(false)'));
    assert(callback.lastIndexOf('setLoading(false)') > callback.lastIndexOf('endResetModel()'));
}
const resolver = read('src/playbackresolver.cpp');
assert(resolver.includes('m_prefetchReplies.size() >= 2'));
assert(resolver.includes('m_prefetchedResponses.size() >= 16'));
assert(resolver.includes('m_prefetchedResponses.erase(it)'));

const decoder = read('src/droidvideodecoder.cpp');
const stop = block(decoder, 'void DroidVideoDecoder::stop()');
assert(stop.includes('interruptedCodec = m_startedCodec.load()'));
assert(stop.indexOf('m_stop.store(true)') < stop.indexOf('m_startedCodec.load()'));
assert(stop.indexOf('m_demuxThread.join()') < stop.indexOf('if (m_codec'));
assert(decoder.indexOf('m_startedCodec.store(m_codec)') > decoder.indexOf('if (!droid_media_codec_start(m_codec))'));
assert(decoder.includes('m_startedCodec.store(m_codec);\n    if (m_stop.load()) return false;'));
// Enumerate all seq-cst orders of the publication/cancellation handshake.
// This is a concurrency-policy check, not a simulation of a real OMX driver.
let orders = 0;
function interleave(gui, worker, stopped = false, published = false,
                    guiSawStarted = false, workerSawStop = false) {
    if (!gui.length && !worker.length) {
        assert(guiSawStarted || workerSawStop, 'cancellation must not be missed by both threads');
        ++orders;
        return;
    }
    if (gui.length) {
        if (gui[0] === 'stop')
            interleave(gui.slice(1), worker, true, published, guiSawStarted, workerSawStop);
        else
            interleave(gui.slice(1), worker, stopped, published, published, workerSawStop);
    }
    if (worker.length) {
        if (worker[0] === 'publish')
            interleave(gui, worker.slice(1), stopped, true, guiSawStarted, workerSawStop);
        else
            interleave(gui, worker.slice(1), stopped, published, guiSawStarted, stopped);
    }
}
interleave(['stop', 'readStarted'], ['publish', 'readStop']);
assert.equal(orders, 6);
console.log('home_scroll_smoke=ready|qml_policy=executed|source_contracts=passed|device_performance=not-tested');
