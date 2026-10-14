'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const read = file => fs.readFileSync(path.join(__dirname, '..', 'qml', file), 'utf8');
const images = vm.createContext({});
vm.runInContext(read('components/ImageUrls.js').replace('.pragma library', ''), images);
const thumb = (url, width) => images.thumbnail(url, width);
const original = 'http://i1.hdslb.com/bfs/archive/test.jpg';
assert.equal(thumb(original, 450), 'https://i1.hdslb.com/bfs/archive/test.jpg@480w_1s.webp');
assert.equal(thumb(original, 470), thumb(original, 450), 'nearby widths must share cache');
assert.equal(thumb(original, 9000), 'https://i1.hdslb.com/bfs/archive/test.jpg@1280w_1s.webp');
for (const url of ['https://i0.hdslb.com/a.gif', 'https://example.com/a.jpg',
                    original + '?token=signed', original + '@160w.webp', 'qrc:/logo.png', ''])
    assert.equal(thumb(url, 160), url, 'preserve signed/transformed/local/animated URLs');
function body(source, marker) {
    const start = source.indexOf(marker);
    assert(start >= 0, marker);
    const open = source.indexOf('{', start);
    let depth = 1, end = open + 1;
    for (; depth; ++end) {
        if (source[end] === '{') ++depth;
        if (source[end] === '}') --depth;
    }
    return source.slice(open + 1, end - 1);
}
const detail = read('pages/VideoDetailPage.qml');
let comments = 0, related = 0;
const state = vm.createContext({detailReady: true, status: 1, PageStatus: {Active: 1},
    playbackSettled: false, requestComments: () => ++comments, requestRelated: () => ++related});
const run = () => vm.runInContext(`(function(){${body(detail, 'function maybeLoadSupplementaryContent()')}})()`, state);
run();
assert.equal(comments, 1, 'comments must not wait for playback settling or scrolling');
assert.equal(related, 1, 'recommendations must fetch alongside comments');
state.status = 0; run(); assert.equal(comments, 1, 'inactive pages do not start requests');
state.status = 1; state.detailReady = false; run(); assert.equal(related, 1);
const requests = vm.createContext({commentRequestIssued: false, relatedRequestIssued: false,
    commentRequestCount: 0, relatedRequestCount: 0, videoDetail: {aid: '123'},
    videoBvid: 'BV123', commentModel: {loading: false, load: () => ++comments},
    relatedModel: {loading: false, load: () => ++related}, console: {log() {}}});
const request = kind => vm.runInContext(
    `(function(reason){${body(detail, `function request${kind}(reason)`)}})('test')`, requests);
for (let i = 0; i < 100; ++i) { request('Comments'); request('Related'); }
assert.equal(requests.commentRequestCount, 1, 'activation/metadata notifications must coalesce');
assert.equal(requests.relatedRequestCount, 1, 'loaded data must not refetch on return');
requests.commentRequestIssued = false; requests.commentModel.loading = true;
assert.equal(request('Comments'), false, 'opening all comments reuses an in-flight request');
assert(!/id: (commentLoadTimer|relatedLoadTimer|commentRevealTimer|relatedRevealTimer|detailRevealTimer)/.test(detail));
console.log('ui_loading_smoke=ready|cdn_policy=executed|detail_request_policy=executed|device_validation=required');
