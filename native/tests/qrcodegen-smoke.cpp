#include <qrcodegen.hpp>

#include <iostream>

int main() {
    const qrcodegen::QrCode qr = qrcodegen::QrCode::encodeText(
                "https://passport.bilibili.com/silisili-qr-smoke",
                qrcodegen::QrCode::Ecc::MEDIUM);
    const int size = qr.getSize();
    int darkModules = 0;
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x)
            darkModules += qr.getModule(x, y) ? 1 : 0;
    }
    if (size < 21 || darkModules <= 0
            || !qr.getModule(0, 0) || !qr.getModule(6, 0)
            || !qr.getModule(0, 6) || !qr.getModule(6, 6)) {
        std::cerr << "qr_builtin_smoke=failed\n";
        return 1;
    }
    std::cout << "qr_builtin_smoke=ready|modules=" << size
              << "|dark=" << darkModules << "\n";
    return 0;
}
