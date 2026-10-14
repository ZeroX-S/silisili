.pragma library

// Stable CDN size buckets share cache entries across single/double columns.
// Never rewrite signed URLs, existing transforms, animations, or other hosts.
function thumbnail(source, width) {
    var url = String(source || "")
    if (url.indexOf("//") === 0) url = "https:" + url
    if (!/^https?:\/\/[^/]+\.(hdslb\.com|biliimg\.com)\//i.test(url)
            || /[?@#]/.test(url) || !/\.(jpe?g|png|webp)$/i.test(url))
        return url
    var target = Math.max(1, width || 640)
    var buckets = [160, 320, 480, 640, 960, 1280]
    var size = 1280
    for (var i = 0; i < buckets.length; ++i) {
        if (target <= buckets[i]) { size = buckets[i]; break }
    }
    return url.replace(/^http:/, "https:") + "@" + size + "w_1s.webp"
}
