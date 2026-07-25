//
// Created by fang on 2024/1/8.
//

#include <algorithm>
#include <cmath>

#include <borealis/core/thread.hpp>
#include <borealis/core/view.hpp>
#include <borealis/core/application.hpp>

#include "utils/gesture_helper.hpp"

#ifdef SILISILI_SAILFISH_MOBILE

namespace {
constexpr float MOBILE_PAN_THRESHOLD = 16.0f;
constexpr float MOBILE_DOUBLE_TAP_DISTANCE = 32.0f;
constexpr int64_t MOBILE_DOUBLE_TAP_US = 280000;

float pointDistance(const brls::Point& a, const brls::Point& b) {
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

bool isCenterTap(const brls::Rect& frame, const brls::Point& point) {
    const float left = frame.getMinX() + frame.getWidth() * 0.25f;
    const float right = frame.getMaxX() - frame.getWidth() * 0.25f;
    const float top = frame.getMinY() + frame.getHeight() * 0.20f;
    const float bottom = frame.getMaxY() - frame.getHeight() * 0.20f;
    return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom;
}
}  // namespace

#endif

// Delta from touch starting point to current, when
// touch will be recognized as pan movement
#define MAX_DELTA_MOVEMENT 24

// Time in ms to recognize long press
#define LONG_TIME_MS 250  // 250ms
#define LONG_TIME_US (LONG_TIME_MS * 1000)

OsdGestureRecognizer::OsdGestureRecognizer(const OsdGestureEvent::Callback& respond) {
    tapEvent.subscribe(respond);
    this->startTime = 0;
    this->endTime   = -1 - LONG_TIME_US;
}

/// 触摸被打断时保证触发对应的完结事件
static inline OsdGestureType updateGestureType(OsdGestureType osdGestureType) {
    if (osdGestureType == OsdGestureType::LONG_PRESS_START) {
        return OsdGestureType::LONG_PRESS_CANCEL;
    } else if (osdGestureType == OsdGestureType::LEFT_VERTICAL_PAN_START ||
               osdGestureType == OsdGestureType::LEFT_VERTICAL_PAN_UPDATE) {
        return OsdGestureType::LEFT_VERTICAL_PAN_CANCEL;
    } else if (osdGestureType == OsdGestureType::RIGHT_VERTICAL_PAN_START ||
               osdGestureType == OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE) {
        return OsdGestureType::RIGHT_VERTICAL_PAN_CANCEL;
    } else if (osdGestureType == OsdGestureType::HORIZONTAL_PAN_START ||
               osdGestureType == OsdGestureType::HORIZONTAL_PAN_UPDATE) {
        return OsdGestureType::HORIZONTAL_PAN_CANCEL;
    } else if (osdGestureType == OsdGestureType::PINCH_START ||
               osdGestureType == OsdGestureType::PINCH_UPDATE) {
        return OsdGestureType::PINCH_CANCEL;
    }
    return osdGestureType;
}

brls::GestureState OsdGestureRecognizer::recognitionLoop(brls::TouchState touch, brls::MouseState mouse,
                                                         brls::View* view, brls::Sound* soundToPlay) {
#ifdef SILISILI_SAILFISH_MOBILE
    brls::TouchPhase phase = touch.phase;
    brls::Point currentPosition = touch.position;
    int fingerId = touch.fingerId;

    if (phase == brls::TouchPhase::NONE) {
        phase = mouse.leftButton;
        currentPosition = mouse.position;
        fingerId = -1;
    }
    if (!enabled || phase == brls::TouchPhase::NONE)
        return brls::GestureState::FAILED;

    auto fire = [this](OsdGestureType type, brls::GestureState gestureState,
                       const brls::Point& eventPosition) {
        this->osdGestureType = type;
        this->state = gestureState;
        this->position = eventPosition;
        this->tapEvent.fire(getCurrentStatus());
    };

    auto clearGesture = [this]() {
        this->activeFingers.clear();
        this->primaryFinger = -1;
        this->pinchFingerA = -1;
        this->pinchFingerB = -1;
        this->pinchActive = false;
        this->suppressUntilRelease = false;
        this->pinchStartDistance = 0.0f;
        this->gestureScale = 1.0f;
        this->deltaX = 0.0f;
        this->deltaY = 0.0f;
        this->osdGestureType = OsdGestureType::NONE;
    };

    // wl_touch.cancel is terminal for the whole touch sequence. Application
    // interrupts recognizers first, so cancellation must be handled before
    // the generic INTERRUPTED path below.
    if (touch.canceled) {
        OsdGestureType cancelType = updateGestureType(this->osdGestureType);
        if (cancelType != this->osdGestureType || cancelType == OsdGestureType::PINCH_CANCEL)
            fire(cancelType, brls::GestureState::FAILED, currentPosition);
        this->pendingTap = false;
        ++this->tapGeneration;
        clearGesture();
        this->lastState = this->state = brls::GestureState::FAILED;
        return this->state;
    }

    if (phase != brls::TouchPhase::START &&
        (this->state == brls::GestureState::INTERRUPTED || this->state == brls::GestureState::FAILED)) {
        this->activeFingers.erase(fingerId);
        if (this->activeFingers.empty())
            clearGesture();
        this->lastState = this->state;
        return this->state;
    }

    brls::Rect frame = view->getFrame();
    switch (phase) {
        case brls::TouchPhase::START: {
            brls::Application::giveFocus(view);
            this->activeFingers[fingerId] = {currentPosition, currentPosition};

            if (this->activeFingers.size() == 1) {
                this->primaryFinger = fingerId;
                this->startTime = brls::getCPUTimeUsec();
                this->position = currentPosition;
                this->deltaX = 0.0f;
                this->deltaY = 0.0f;
                this->gestureScale = 1.0f;
                this->osdGestureType = OsdGestureType::NONE;

                const bool timely = this->pendingTap &&
                    this->startTime - this->endTime <= MOBILE_DOUBLE_TAP_US;
                const bool nearby = pointDistance(this->lastTapPosition, currentPosition) <=
                    MOBILE_DOUBLE_TAP_DISTANCE;
                if (timely && nearby && isCenterTap(frame, this->lastTapPosition) &&
                    isCenterTap(frame, currentPosition)) {
                    this->pendingTap = false;
                    ++this->tapGeneration;
                    this->osdGestureType = OsdGestureType::DOUBLE_TAP_START;
                } else if (this->pendingTap) {
                    // The second contact cannot form a center double tap. Emit
                    // the completed first tap now and start a fresh sequence.
                    this->pendingTap = false;
                    ++this->tapGeneration;
                    OsdGestureStatus firstTap{
                        .osdGestureType = OsdGestureType::TAP,
                        .state = brls::GestureState::END,
                        .position = this->lastTapPosition,
                        .deltaX = 0.0f,
                        .deltaY = 0.0f,
                        .scale = 1.0f,
                    };
                    this->tapEvent.fire(firstTap);
                }
                this->state = brls::GestureState::UNSURE;
            } else if (this->activeFingers.size() == 2 && !this->pinchActive) {
                OsdGestureType cancelType = updateGestureType(this->osdGestureType);
                if (cancelType != this->osdGestureType)
                    fire(cancelType, brls::GestureState::FAILED, currentPosition);

                this->pendingTap = false;
                ++this->tapGeneration;
                this->pinchFingerA = this->primaryFinger;
                this->pinchFingerB = fingerId;
                const auto& a = this->activeFingers.at(this->pinchFingerA).position;
                const auto& b = this->activeFingers.at(this->pinchFingerB).position;
                this->pinchStartDistance = std::max(pointDistance(a, b), 1.0f);
                this->gestureScale = 1.0f;
                this->pinchActive = true;
                fire(OsdGestureType::PINCH_START, brls::GestureState::START, currentPosition);
            }
            break;
        }

        case brls::TouchPhase::STAY: {
            auto finger = this->activeFingers.find(fingerId);
            if (finger == this->activeFingers.end())
                break;
            finger->second.position = currentPosition;

            if (this->suppressUntilRelease) {
                this->state = brls::GestureState::STAY;
                break;
            }
            if (this->pinchActive) {
                const auto a = this->activeFingers.find(this->pinchFingerA);
                const auto b = this->activeFingers.find(this->pinchFingerB);
                if (a != this->activeFingers.end() && b != this->activeFingers.end()) {
                    this->gestureScale = pointDistance(a->second.position, b->second.position) /
                        this->pinchStartDistance;
                    fire(OsdGestureType::PINCH_UPDATE, brls::GestureState::STAY, currentPosition);
                }
                break;
            }
            if (fingerId != this->primaryFinger)
                break;
            if (!frame.pointInside(currentPosition)) {
                OsdGestureType cancelType = updateGestureType(this->osdGestureType);
                if (cancelType != this->osdGestureType)
                    fire(cancelType, brls::GestureState::FAILED, currentPosition);
                else
                    this->state = brls::GestureState::FAILED;
                break;
            }

            const brls::Point movement = currentPosition - finger->second.origin;
            this->position = currentPosition;
            if (this->osdGestureType == OsdGestureType::NONE ||
                this->osdGestureType == OsdGestureType::DOUBLE_TAP_START) {
                if (std::fabs(movement.x) > MOBILE_PAN_THRESHOLD &&
                    std::fabs(movement.x) >= std::fabs(movement.y)) {
                    this->osdGestureType = OsdGestureType::HORIZONTAL_PAN_START;
                    this->deltaX = movement.x / std::max(frame.getWidth(), 1.0f);
                } else if (std::fabs(movement.y) > MOBILE_PAN_THRESHOLD) {
                    this->osdGestureType = currentPosition.x < frame.getMidX()
                        ? OsdGestureType::LEFT_VERTICAL_PAN_START
                        : OsdGestureType::RIGHT_VERTICAL_PAN_START;
                    this->deltaY = -movement.y / std::max(frame.getHeight(), 1.0f);
                } else if (brls::getCPUTimeUsec() - this->startTime > LONG_TIME_US &&
                           this->osdGestureType == OsdGestureType::NONE) {
                    this->osdGestureType = OsdGestureType::LONG_PRESS_START;
                } else {
                    break;
                }
                fire(this->osdGestureType, brls::GestureState::START, currentPosition);
            } else if (this->osdGestureType == OsdGestureType::HORIZONTAL_PAN_START ||
                       this->osdGestureType == OsdGestureType::HORIZONTAL_PAN_UPDATE) {
                this->deltaX = movement.x / std::max(frame.getWidth(), 1.0f);
                fire(OsdGestureType::HORIZONTAL_PAN_UPDATE, brls::GestureState::STAY, currentPosition);
            } else if (this->osdGestureType == OsdGestureType::LEFT_VERTICAL_PAN_START ||
                       this->osdGestureType == OsdGestureType::LEFT_VERTICAL_PAN_UPDATE) {
                this->deltaY = -movement.y / std::max(frame.getHeight(), 1.0f);
                fire(OsdGestureType::LEFT_VERTICAL_PAN_UPDATE, brls::GestureState::STAY, currentPosition);
            } else if (this->osdGestureType == OsdGestureType::RIGHT_VERTICAL_PAN_START ||
                       this->osdGestureType == OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE) {
                this->deltaY = -movement.y / std::max(frame.getHeight(), 1.0f);
                fire(OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE, brls::GestureState::STAY, currentPosition);
            }
            break;
        }

        case brls::TouchPhase::END: {
            this->endTime = brls::getCPUTimeUsec();
            if (this->pinchActive && (fingerId == this->pinchFingerA || fingerId == this->pinchFingerB)) {
                fire(OsdGestureType::PINCH_END, brls::GestureState::END, currentPosition);
                this->pinchActive = false;
                this->suppressUntilRelease = true;
            } else if (!this->suppressUntilRelease && fingerId == this->primaryFinger) {
                switch (this->osdGestureType) {
                    case OsdGestureType::DOUBLE_TAP_START:
                        fire(OsdGestureType::DOUBLE_TAP_END, brls::GestureState::END, currentPosition);
                        break;
                    case OsdGestureType::LONG_PRESS_START:
                        fire(OsdGestureType::LONG_PRESS_END, brls::GestureState::END, currentPosition);
                        break;
                    case OsdGestureType::HORIZONTAL_PAN_START:
                    case OsdGestureType::HORIZONTAL_PAN_UPDATE:
                        fire(OsdGestureType::HORIZONTAL_PAN_END, brls::GestureState::END, currentPosition);
                        break;
                    case OsdGestureType::LEFT_VERTICAL_PAN_START:
                    case OsdGestureType::LEFT_VERTICAL_PAN_UPDATE:
                        fire(OsdGestureType::LEFT_VERTICAL_PAN_END, brls::GestureState::END, currentPosition);
                        break;
                    case OsdGestureType::RIGHT_VERTICAL_PAN_START:
                    case OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE:
                        fire(OsdGestureType::RIGHT_VERTICAL_PAN_END, brls::GestureState::END, currentPosition);
                        break;
                    default: {
                        this->lastTapPosition = currentPosition;
                        this->pendingTap = true;
                        const uint64_t generation = ++this->tapGeneration;
                        OsdGestureStatus tapStatus{
                            .osdGestureType = OsdGestureType::TAP,
                            .state = brls::GestureState::END,
                            .position = currentPosition,
                            .deltaX = 0.0f,
                            .deltaY = 0.0f,
                            .scale = 1.0f,
                        };
                        ASYNC_RETAIN
                        iter = brls::delay(MOBILE_DOUBLE_TAP_US / 1000, [ASYNC_TOKEN, generation, tapStatus]() {
                            ASYNC_RELEASE
                            if (!this->pendingTap || this->tapGeneration != generation)
                                return;
                            this->pendingTap = false;
                            this->tapEvent.fire(tapStatus);
                        });
                        this->state = brls::GestureState::END;
                        break;
                    }
                }
            }

            this->activeFingers.erase(fingerId);
            if (this->activeFingers.empty())
                clearGesture();
            break;
        }
        case brls::TouchPhase::NONE:
            this->state = brls::GestureState::FAILED;
            break;
    }

    this->lastState = this->state;
    return this->state;
#else
    brls::TouchPhase phase = touch.phase;
    brls::Point position   = touch.position;

    if (phase == brls::TouchPhase::NONE) {
        position = mouse.position;
        phase    = mouse.leftButton;
    }

    if (!enabled || phase == brls::TouchPhase::NONE) return brls::GestureState::FAILED;

    // If not first touch frame and state is
    // INTERRUPTED or FAILED, stop recognition
    if (phase != brls::TouchPhase::START) {
        if (this->state == brls::GestureState::INTERRUPTED || this->state == brls::GestureState::FAILED) {
            if (this->state != lastState) {
                // 触摸被打断时保证触发对应的完结事件
                this->osdGestureType = updateGestureType(this->osdGestureType);
                this->tapEvent.fire(getCurrentStatus());
            }

            lastState = this->state;
            return this->state;
        }
    }

    switch (phase) {
        case brls::TouchPhase::START:
            brls::Application::giveFocus(view);
            this->startTime = brls::getCPUTimeUsec();
            if (this->startTime - this->endTime < LONG_TIME_US) {
                brls::cancelDelay(iter);
                this->osdGestureType = OsdGestureType::DOUBLE_TAP_START;
            } else {
                this->osdGestureType = OsdGestureType::NONE;
            }

            this->state    = brls::GestureState::UNSURE;
            this->position = position;
            this->tapEvent.fire(getCurrentStatus());
            break;
        case brls::TouchPhase::STAY: {
            auto frame = view->getFrame();
            // Check if touch is out view's bounds
            // if true, FAIL recognition
            if (!frame.pointInside(position)) {
                // 触摸被打断时保证触发对应的完结事件
                this->state          = brls::GestureState::FAILED;
                this->osdGestureType = updateGestureType(this->osdGestureType);
            } else if (this->osdGestureType == OsdGestureType::NONE) {
                // 到目前还没有识别出具体的触摸类型
                this->delta = position - this->position;
                if (fabs(this->delta.x) > MAX_DELTA_MOVEMENT) {
                    // 识别到水平滑动
                    this->osdGestureType = OsdGestureType::HORIZONTAL_PAN_START;
                } else if (fabs(this->delta.y) > MAX_DELTA_MOVEMENT) {
                    // 识别到垂直滑动
                    if (position.x < frame.getMidX()) {
                        this->osdGestureType = OsdGestureType::LEFT_VERTICAL_PAN_START;
                    } else {
                        this->osdGestureType = OsdGestureType::RIGHT_VERTICAL_PAN_START;
                    }
                } else if (brls::getCPUTimeUsec() - this->startTime > LONG_TIME_US) {
                    // 识别到长按
                    this->osdGestureType = OsdGestureType::LONG_PRESS_START;
                } else {
                    // 没有识别到触摸类型，不触发回调函数
                    break;
                }
            } else if (this->osdGestureType == OsdGestureType::HORIZONTAL_PAN_START ||
                       this->osdGestureType == OsdGestureType::HORIZONTAL_PAN_UPDATE) {
                // 更新水平滑动的状态
                this->delta          = position - this->position;
                this->deltaX         = delta.x / frame.size.width;
                this->osdGestureType = OsdGestureType::HORIZONTAL_PAN_UPDATE;
            } else if (this->osdGestureType == OsdGestureType::LEFT_VERTICAL_PAN_START ||
                       this->osdGestureType == OsdGestureType::LEFT_VERTICAL_PAN_UPDATE) {
                // 更新左侧垂直滑动的状态
                this->delta          = position - this->position;
                this->deltaY         = -delta.y / frame.size.height;
                this->osdGestureType = OsdGestureType::LEFT_VERTICAL_PAN_UPDATE;
            } else if (this->osdGestureType == OsdGestureType::RIGHT_VERTICAL_PAN_START ||
                       this->osdGestureType == OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE) {
                // 更新右侧垂直滑动的状态
                this->delta          = position - this->position;
                this->deltaY         = -delta.y / frame.size.height;
                this->osdGestureType = OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE;
            } else {
                break;
            }
            this->tapEvent.fire(getCurrentStatus());
            break;
        }

        case brls::TouchPhase::END: {
            this->endTime = brls::getCPUTimeUsec();
            this->state   = brls::GestureState::END;

            switch (this->osdGestureType) {
                case OsdGestureType::DOUBLE_TAP_START:
                    this->osdGestureType = OsdGestureType::DOUBLE_TAP_END;
                    this->tapEvent.fire(getCurrentStatus());
                    break;
                case OsdGestureType::LONG_PRESS_START:
                    this->osdGestureType = OsdGestureType::LONG_PRESS_END;
                    this->tapEvent.fire(getCurrentStatus());
                    break;
                case OsdGestureType::HORIZONTAL_PAN_START:
                case OsdGestureType::HORIZONTAL_PAN_UPDATE:
                    // 避免拖拽结束后立刻触摸被误认为是双击事件
                    this->endTime        = 0;
                    this->osdGestureType = OsdGestureType::HORIZONTAL_PAN_END;
                    this->tapEvent.fire(getCurrentStatus());
                    break;
                case OsdGestureType::LEFT_VERTICAL_PAN_START:
                case OsdGestureType::LEFT_VERTICAL_PAN_UPDATE:
                    this->endTime        = 0;
                    this->osdGestureType = OsdGestureType::LEFT_VERTICAL_PAN_END;
                    this->tapEvent.fire(getCurrentStatus());
                    break;
                case OsdGestureType::RIGHT_VERTICAL_PAN_START:
                case OsdGestureType::RIGHT_VERTICAL_PAN_UPDATE:
                    this->endTime        = 0;
                    this->osdGestureType = OsdGestureType::RIGHT_VERTICAL_PAN_END;
                    this->tapEvent.fire(getCurrentStatus());
                    break;
                default:
                    this->osdGestureType = OsdGestureType::TAP;
                    brls::cancelDelay(iter);
                    ASYNC_RETAIN
                    iter = brls::delay(LONG_TIME_MS, [ASYNC_TOKEN]() {
                        ASYNC_RELEASE
                        // 延时触发点击事件
                        this->tapEvent.fire(getCurrentStatus());
                    });
                    break;
            }
            break;
        }
        case brls::TouchPhase::NONE:
            this->state = brls::GestureState::FAILED;
            break;
    }

    lastState = this->state;
    return this->state;
#endif
}

OsdGestureStatus OsdGestureRecognizer::getCurrentStatus() {
    return OsdGestureStatus{
        .osdGestureType = this->osdGestureType,
        .state          = this->state,
        .position       = this->position,
        .deltaX         = this->deltaX,
        .deltaY         = this->deltaY,
        .scale          = this->gestureScale,
    };
}