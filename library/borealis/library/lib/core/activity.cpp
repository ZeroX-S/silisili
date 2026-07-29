/*
    Copyright 2020 natinusala

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

#include <borealis/core/activity.hpp>
#include <borealis/core/application.hpp>
#include <borealis/core/gesture.hpp>
#include <borealis/core/i18n.hpp>
#include <borealis/core/thread.hpp>

#include <algorithm>
#include <cmath>

using namespace brls::literals;

namespace brls
{

#ifdef SILISILI_SAILFISH_MOBILE
namespace
{
constexpr float SAILFISH_BACK_DIRECTION_LOCK = 1.4f;
constexpr float SAILFISH_BACK_START_DISTANCE = 10.0f;
constexpr float SAILFISH_BACK_COMMIT_FRACTION = 0.28f;

class SailfishPageBackGestureRecognizer : public GestureRecognizer
{
  public:
    explicit SailfishPageBackGestureRecognizer(Activity* activity)
        : activity(activity)
    {
    }

    GestureState recognitionLoop(TouchState touch, MouseState, View* view, Sound*) override
    {
        if (!enabled || touch.phase == TouchPhase::NONE)
            return GestureState::FAILED;

        if (touch.phase == TouchPhase::START)
        {
            this->fingerId = touch.fingerId;
            this->startPosition = touch.position;
            this->state = GestureState::UNSURE;
            this->dragging = false;
            view->setTranslationX(0.0f);
            return this->state;
        }

        if (touch.fingerId != this->fingerId)
            return this->fail(view);

        if (this->state == GestureState::INTERRUPTED || this->state == GestureState::FAILED)
            return this->fail(view);

        const float distanceX = touch.position.x - this->startPosition.x;
        const float distanceY = touch.position.y - this->startPosition.y;

        if (this->state == GestureState::UNSURE)
        {
            if (touch.phase == TouchPhase::END)
                return this->fail(view);

            if (std::hypot(distanceX, distanceY) < SAILFISH_BACK_START_DISTANCE)
                return this->state;

            if (distanceX <= 0.0f || distanceX < std::fabs(distanceY) * SAILFISH_BACK_DIRECTION_LOCK ||
                !this->canStart())
                return this->fail(view);

            this->dragging = true;
            this->state = GestureState::START;
            Logger::info("Sailfish page back swipe: started at {:.0f},{:.0f}",
                         this->startPosition.x, this->startPosition.y);
        }
        else if (touch.phase == TouchPhase::STAY)
        {
            this->state = GestureState::STAY;
        }

        if (!this->dragging)
            return this->state;

        const float width = std::max(1.0f, view->getWidth());
        view->setTranslationX(std::clamp(distanceX, 0.0f, width));

        if (touch.phase != TouchPhase::END)
            return this->state;

        const bool commit = distanceX >= width * SAILFISH_BACK_COMMIT_FRACTION;
        view->setTranslationX(0.0f);
        this->dragging = false;
        this->fingerId = -1;
        this->state = GestureState::END;

        Logger::info("Sailfish page back swipe: {} distance={:.0f} threshold={:.0f}",
                     commit ? "committed" : "cancelled", distanceX,
                     width * SAILFISH_BACK_COMMIT_FRACTION);

        if (commit)
        {
            Activity* expectedActivity = this->activity;
            brls::delay(1, [expectedActivity]() {
                auto stack = Application::getActivitiesStack();
                if (stack.size() > 1 && stack.back() == expectedActivity)
                    Application::onControllerButtonPressed(BUTTON_B, false);
            });
        }

        return this->state;
    }

  private:
    bool canStart() const
    {
        auto stack = Application::getActivitiesStack();
        return stack.size() > 1 && stack.back() == this->activity &&
               this->activity->allowsSailfishPageBackGesture(this->startPosition);
    }

    GestureState fail(View* view)
    {
        if (this->dragging)
            view->setTranslationX(0.0f);
        this->dragging = false;
        this->fingerId = -1;
        this->state = GestureState::FAILED;
        return this->state;
    }

    Activity* activity;
    Point startPosition;
    int fingerId = -1;
    bool dragging = false;
};
} // namespace
#endif

Activity::Activity()
{
}

Activity::Activity(View* view)
    : constructorView(view)
{
}

void Activity::setContentView(View* view)
{
    if (this->contentView)
    {
        this->contentView->setParentActivity(nullptr);
        this->contentView->willDisappear();
        delete this->contentView;
    }

    this->contentView = view;
    this->contentView->setParentActivity(this);
#ifdef SILISILI_SAILFISH_MOBILE
    this->contentView->addGestureRecognizer(new SailfishPageBackGestureRecognizer(this));
#endif
    // willAppear is only called when the activity is pushed onto the stack

    this->resizeToFitWindow();
}

void Activity::resizeToFitWindow()
{
    if (!this->contentView)
        return;

    this->contentView->setDimensions(Application::contentWidth, Application::contentHeight);
}

View* Activity::createContentView()
{
    return constructorView;
}

float Activity::getShowAnimationDuration(TransitionAnimation animation)
{
    return contentView->getShowAnimationDuration(animation);
}

void Activity::onWindowSizeChanged()
{
    this->resizeToFitWindow();
}

bool Activity::isTranslucent()
{
    if (!this->contentView)
        return true;

    return this->contentView->isTranslucent();
}

void Activity::willAppear(bool resetState)
{
    if (this->contentView)
        this->contentView->willAppear(resetState);
}

void Activity::willDisappear(bool resetState)
{
    if (this->contentView)
        this->contentView->willDisappear(resetState);
}

void Activity::setInFadeAnimation(bool inFadeAnimation)
{
    if (this->contentView)
        this->contentView->setInFadeAnimation(inFadeAnimation);
}

void Activity::show(std::function<void(void)> cb, bool animate, float animationDuration)
{
    if (this->contentView)
        this->contentView->show(cb, animate, animationDuration);
}

void Activity::hide(std::function<void(void)> cb, bool animate, float animationDuration)
{
    if (this->contentView)
        this->contentView->hide(cb, animate, animationDuration);
}

bool Activity::isHidden()
{
    if (!this->contentView)
        return false;

    return this->contentView->isHidden();
}

ActionIdentifier Activity::registerAction(const std::string& hintText, const enum ControllerButton button, const ActionListener& actionListener, const bool hidden, const bool allowRepeating, const enum Sound sound)
{
    if (this->contentView)
        return this->contentView->registerAction(hintText, button, actionListener, hidden, allowRepeating, sound);

    return ACTION_NONE;
}

ActionIdentifier Activity::registerAction(const BrlsKeyCombination key, const ActionListener& actionListener, const bool allowRepeating)
{
    if (this->contentView)
        return this->contentView->registerAction(key, actionListener, allowRepeating);

    return ACTION_NONE;
}

void Activity::unregisterAction(ActionIdentifier identifier)
{
    if (this->contentView)
        this->contentView->unregisterAction(identifier);
}

ActionIdentifier Activity::registerExitAction(enum ControllerButton button)
{
    if (this->contentView)
        return this->contentView->registerAction("hints/exit"_i18n, button, [](View* view) { Application::quit(); return true; });

    return ACTION_NONE;
}

View* Activity::getDefaultFocus()
{
    if (!this->contentView)
        return nullptr;

    return this->contentView->getDefaultFocus();
}

void Activity::setAlpha(float alpha)
{
    if (this->contentView)
        this->contentView->setAlpha(alpha);
}

View* Activity::getContentView()
{
    return this->contentView;
}

bool Activity::allowsSailfishPageBackGesture(Point) const
{
    return true;
}

View* Activity::getView(std::string id)
{
    if (!this->contentView)
        return nullptr;

    return this->contentView->getView(id);
}

Activity::~Activity()
{
    if (this->contentView)
    {
        this->contentView->willDisappear();

        this->contentView->freeView();
        this->contentView = nullptr;
    }
}

} // namespace brls
