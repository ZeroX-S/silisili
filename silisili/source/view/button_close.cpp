//
// Created by fang on 2022/12/27.
//

#include <borealis/core/touch/tap_gesture.hpp>
#include <borealis/views/label.hpp>

#include <utility>

#include "view/button_close.hpp"

ButtonClose::ButtonClose() {
    this->inflateFromXMLRes("xml/views/button_close.xml");
    brls::Logger::debug("View ButtonClose: create");

#ifdef SILISILI_SAILFISH_MOBILE
    // This label is an icon glyph, not UI copy. Compensate for the global
    // phone text scale so the visible close icon is about 27 logical units
    // inside a native-sized 48-unit touch target.
    this->label->setFontSize(34);
#endif

    this->registerColorXMLAttribute("textColor", [this](NVGcolor value) { this->setTextColor(value); });

    this->registerClickAction([this](...) {
        if (this->customCloseAction)
            this->customCloseAction();
        else
            this->dismiss();
        return true;
    });
    this->addGestureRecognizer(new brls::TapGestureRecognizer(this));
}

void ButtonClose::setTextColor(NVGcolor color) { this->label->setTextColor(color); }

void ButtonClose::setCustomCloseAction(std::function<void()> action) {
    this->customCloseAction = std::move(action);
}

ButtonClose::~ButtonClose() { brls::Logger::debug("View ButtonClose: delete"); }

brls::View* ButtonClose::create() { return new ButtonClose(); }
