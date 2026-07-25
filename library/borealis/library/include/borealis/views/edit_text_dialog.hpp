#pragma once
#include <borealis/core/box.hpp>
#include <borealis/views/label.hpp>
#include <borealis/views/button.hpp>
#include <borealis/core/bind.hpp>

namespace brls
{
#ifdef SILISILI_SAILFISH_MOBILE
class SailfishMaliitContext;
#endif
class EditTextDialog : public Box
{
  public:
    EditTextDialog();
    ~EditTextDialog() override;
    void open();
    void setText(const std::string& value);
    void setHeaderText(const std::string& value);
    void setHintText(const std::string& value);
    void setCountText(const std::string& value);
    void setCursor(int cursor);
    bool isTranslucent() override;
    void onLayout() override;
    Event<Point>* getLayoutEvent();
    Event<>* getBackspaceEvent();
    Event<>* getCancelEvent();
    Event<>* getSubmitEvent();
    Event<std::string>* getClipboardEvent();
    void updateUI();
  private:
#ifdef SILISILI_SAILFISH_MOBILE
    friend class SailfishMaliitContext;
#endif
    void dismissInput(bool submit);

    std::string content;
    std::string hint;
    Event<Point> layoutEvent;
    Event<> backspaceEvent, cancelEvent, summitEvent;
    Event<std::string> clipboardEvent;
    bool init = false;
    bool closing = false;

    BRLS_BIND(brls::Label, header, "brls/dialog/header");
    BRLS_BIND(brls::Label, label, "brls/dialog/label");
    BRLS_BIND(brls::Label, count, "brls/dialog/count");
    BRLS_BIND(brls::Box, container, "brls/container");
#ifdef SILISILI_SAILFISH_MOBILE
    BRLS_BIND(brls::Button, backButton, "brls/dialog/back");
    BRLS_BIND(brls::Button, confirmButton, "brls/dialog/confirm");
#endif
};
}
