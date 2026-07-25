//
// Created by fang on 2022/6/9.
//

#include <borealis/core/touch/tap_gesture.hpp>

#include "activity/search_activity_tv.hpp"
#include "fragment/home_tab.hpp"
#include "utils/activity_helper.hpp"
#include "utils/shortcut_helper.hpp"

using namespace brls::literals;

HomeTab::HomeTab() {
    this->inflateFromXMLRes("xml/fragment/home_tab.xml");
    brls::Logger::debug("Fragment HomeTab: create");
}

void HomeTab::onCreate() {
#ifndef SILISILI_SAILFISH_MOBILE
    this->registerTabAction("silisili/search/tab"_i18n, brls::ControllerButton::BUTTON_Y,
                            ShortcutHelper::getSearch(),
                            [](brls::View* view) -> bool {
                                if (TVSearchActivity::TV_MODE) {
                                    Intent::openTVSearch();
                                } else {
                                    brls::Application::getImeManager()->openForText(
                                        [](const std::string& text) { Intent::openSearch(text); },
                                        "silisili/home/common/search"_i18n, "", 32, "", 0);
                                }
                                return true;
                            });
#endif

    this->registerTabAction(
        "上一项", brls::ControllerButton::BUTTON_LB, ShortcutHelper::getLast(),
        [this](brls::View* view) -> bool {
            tabFrame->focus2LastTab();
            return true;
        },
        true);

    this->registerTabAction(
        "下一项", brls::ControllerButton::BUTTON_RB, ShortcutHelper::getNext(),
        [this](brls::View* view) -> bool {
            tabFrame->focus2NextTab();
            return true;
        },
        true);

}

void HomeTab::openSearch() {
#ifdef SILISILI_SAILFISH_MOBILE
    brls::Logger::info("Sailfish search: opening Wayland system IME");
    brls::Application::getImeManager()->openForText([](const std::string& text) { Intent::openSearch(text); },
                                                    "silisili/home/common/search"_i18n, "", 32, "", 0);
#else
    if (TVSearchActivity::TV_MODE) {
        Intent::openTVSearch();
    } else {
        brls::Application::getImeManager()->openForText([](const std::string& text) { Intent::openSearch(text); },
                                                        "silisili/home/common/search"_i18n, "", 32, "", 0);
    }
#endif
}

brls::View* HomeTab::create() { return new HomeTab(); }

HomeTab::~HomeTab() { brls::Logger::debug("Fragment HomeTab: delete"); }
