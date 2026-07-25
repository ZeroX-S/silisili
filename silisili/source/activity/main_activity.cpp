/*
    Copyright 2020-2021 natinusala

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

#include <borealis/core/touch/tap_gesture.hpp>

#include "activity/main_activity.hpp"
#include "utils/activity_helper.hpp"
#include "utils/dialog_helper.hpp"
#include "view/custom_button.hpp"
#include "view/auto_tab_frame.hpp"
#include "view/svg_image.hpp"
#include "fragment/home_tab.hpp"

void MainActivity::onContentAvailable() {
    this->registerAction(
        "Settings", brls::ControllerButton::BUTTON_START,
        [](brls::View* view) -> bool {
            Intent::openSetting();
            return true;
        },
        true);

    this->searchBtn->registerClickAction([](brls::View* view) -> bool {
        HomeTab::openSearch();
        return true;
    });
    this->searchBtn->addGestureRecognizer(
        new brls::TapGestureRecognizer(this->searchBtn, []() { HomeTab::openSearch(); }));

    this->settingBtn->registerClickAction([](brls::View* view) -> bool {
        Intent::openSetting();
        return true;
    });

    this->settingBtn->getFocusEvent()->subscribe([this](bool value) {
        SVGImage* image = dynamic_cast<SVGImage*>(this->settingBtn->getChildren()[0]);
        if (!image) return;
        if (value) {
            image->setImageFromSVGRes("svg/ico-setting-activate.svg");
        } else {
            image->setImageFromSVGRes("svg/ico-setting.svg");
        }
    });

    this->settingBtn->addGestureRecognizer(new brls::TapGestureRecognizer(this->settingBtn));

    this->inboxBtn->registerClickAction([](brls::View* view) -> bool {
        if (DialogHelper::checkLogin()) Intent::openInbox();
        return true;
    });

    this->inboxBtn->getFocusEvent()->subscribe([this](bool value) {
        SVGImage* image = dynamic_cast<SVGImage*>(this->inboxBtn->getChildren()[0]);
        if (!image) return;
        if (value) {
            image->setImageFromSVGRes("svg/ico-inbox-activate.svg");
        } else {
            image->setImageFromSVGRes("svg/ico-inbox.svg");
        }
    });
    this->inboxBtn->addGestureRecognizer(new brls::TapGestureRecognizer(this->inboxBtn));
#ifdef SILISILI_SAILFISH_MOBILE
    this->tabFrame->getSidebar()->setJustifyContent(brls::JustifyContent::SPACE_EVENLY);
    brls::Logger::info("Sailfish navigation: persistent header and bottom Home/Dynamic/Mine tabs");
#endif
}
