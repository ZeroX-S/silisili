/*
    Copyright 2019  WerWolv
    Copyright 2019  p-sam
    Copyright 2023  xfangfang

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

#include <libretro-common/encodings/utf.h>

#include <borealis/core/box.hpp>
#include <borealis/core/logger.hpp>
#include <borealis/core/thread.hpp>
#include <borealis/platforms/desktop/steam_deck.hpp>
#include <borealis/platforms/glfw/glfw_ime.hpp>
#include <borealis/views/dialog.hpp>
#include <borealis/views/edit_text_dialog.hpp>
#include <borealis/views/label.hpp>
#include <codecvt>
#include <cstring>
#include <iostream>
#include <locale>
#include <algorithm>
#include <cstdlib>

#ifdef SILISILI_SAILFISH_MOBILE
#include <dbus/dbus.h>
#endif

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

namespace brls
{
static int currentIMEStatus = GLFW_FALSE;
#define MAX_PREEDIT_LEN 128
static char preeditBuf[MAX_PREEDIT_LEN] = "";

#ifdef SILISILI_SAILFISH_MOBILE
namespace
{
constexpr const char* MALIIT_ADDRESS_SERVICE = "org.maliit.server";
constexpr const char* MALIIT_ADDRESS_PATH = "/org/maliit/server/address";
constexpr const char* MALIIT_ADDRESS_INTERFACE = "org.maliit.Server.Address";
constexpr const char* MALIIT_SERVER_PATH = "/com/meego/inputmethod/uiserver1";
constexpr const char* MALIIT_SERVER_INTERFACE = "com.meego.inputmethod.uiserver1";
constexpr const char* MALIIT_CLIENT_PATH = "/com/meego/inputmethod/inputcontext";
constexpr const char* MALIIT_CLIENT_INTERFACE = "com.meego.inputmethod.inputcontext1";

std::wstring utf8ToWide(const std::string& text)
{
    return std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(text);
}

void logDBusError(const char* prefix, DBusError* error)
{
    Logger::error("{}: {}", prefix,
                  error && error->message ? error->message : "unknown D-Bus error");
    if (error && dbus_error_is_set(error))
        dbus_error_free(error);
}

bool appendVariant(DBusMessageIter* array, const char* key, int type,
                   const char* signature, const void* value)
{
    DBusMessageIter entry;
    DBusMessageIter variant;
    if (!dbus_message_iter_open_container(array, DBUS_TYPE_DICT_ENTRY, nullptr, &entry))
        return false;
    const char* keyValue = key;
    if (!dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &keyValue) ||
        !dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, signature, &variant) ||
        !dbus_message_iter_append_basic(&variant, type, value) ||
        !dbus_message_iter_close_container(&entry, &variant) ||
        !dbus_message_iter_close_container(array, &entry))
        return false;
    return true;
}
}

class SailfishMaliitContext
{
  public:
    explicit SailfishMaliitContext(GLFWImeManager* owner)
        : owner(owner)
    {
    }

    ~SailfishMaliitContext()
    {
        this->shutdown();
    }

    void activate(bool numberInput)
    {
        this->numberInput = numberInput;
        if (!this->connect())
            return;

        this->active = true;
        if (!this->attributeExtensionRegistered)
            this->attributeExtensionRegistered =
                this->callWithIntString("registerAttributeExtension", 0, "");
        this->call("activateContext");
        this->sendWidgetInformation(true, true);
        this->call("showInputMethod");
        dbus_connection_flush(this->connection);
        Logger::info("Sailfish Maliit input activated: {} keyboard",
                     numberInput ? "number" : "text");
    }

    void retryShow()
    {
        if (!this->active || !this->connection)
            return;
        this->sendWidgetInformation(true, false);
        this->call("showInputMethod");
        dbus_connection_flush(this->connection);
        Logger::info("Sailfish Maliit input show retry");
    }

    void dispatch()
    {
        if (!this->connection || !dbus_connection_get_is_connected(this->connection))
            return;
        dbus_connection_read_write_dispatch(this->connection, 0);
    }

    void deactivate()
    {
        if (!this->connection)
            return;
        if (this->active)
        {
            this->sendWidgetInformation(false, true);
            this->call("reset");
            this->call("hideInputMethod");
            dbus_connection_flush(this->connection);
            Logger::info("Sailfish Maliit input deactivated");
        }
        this->active = false;
        this->preeditReplacementStart = 0;
        this->preeditReplacementLength = 0;
        GLFWImeManager::preeditTextBuffer.clear();
        GLFWImeManager::isEditing = false;
    }

    void commitPreedit()
    {
        if (GLFWImeManager::preeditTextBuffer.empty())
            return;
        this->replaceText(GLFWImeManager::preeditTextBuffer, this->preeditReplacementStart,
                          this->preeditReplacementLength, -1);
    }

    void updateState()
    {
        if (this->active)
            this->sendWidgetInformation(true, false);
    }

  private:
    GLFWImeManager* owner = nullptr;
    DBusConnection* connection = nullptr;
    bool active = false;
    bool numberInput = false;
    bool attributeExtensionRegistered = false;
    int preeditReplacementStart = 0;
    int preeditReplacementLength = 0;

    static DBusHandlerResult messageHandler(DBusConnection* connection,
                                            DBusMessage* message, void* userData)
    {
        auto* context = static_cast<SailfishMaliitContext*>(userData);
        return context->handleMessage(connection, message);
    }

    bool connect()
    {
        if (this->connection && dbus_connection_get_is_connected(this->connection))
            return true;
        this->shutdown();

        std::string address;
        const char* fixedAddress = std::getenv("MALIIT_SERVER_ADDRESS");
        if (fixedAddress && *fixedAddress)
            address = fixedAddress;
        else
            address = this->getServerAddress();
        if (address.empty())
            return false;

        DBusError error;
        dbus_error_init(&error);
        this->connection = dbus_connection_open_private(address.c_str(), &error);
        if (!this->connection)
        {
            logDBusError("Sailfish Maliit peer connection failed", &error);
            return false;
        }
        dbus_connection_set_exit_on_disconnect(this->connection, FALSE);
        static DBusObjectPathVTable vtable = {
            nullptr,
            SailfishMaliitContext::messageHandler,
            nullptr, nullptr, nullptr, nullptr
        };
        if (!dbus_connection_register_object_path(this->connection, MALIIT_CLIENT_PATH,
                                                  &vtable, this))
        {
            Logger::error("Sailfish Maliit client object registration failed");
            this->shutdown();
            return false;
        }
        this->attributeExtensionRegistered =
            this->callWithIntString("registerAttributeExtension", 0, "");
        Logger::info("Sailfish Maliit peer connected: {}", address);
        return true;
    }

    std::string getServerAddress()
    {
        DBusError error;
        dbus_error_init(&error);
        DBusConnection* session = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
        if (!session)
        {
            logDBusError("Sailfish Maliit session-bus connection failed", &error);
            return {};
        }
        dbus_connection_set_exit_on_disconnect(session, FALSE);

        DBusMessage* message = dbus_message_new_method_call(
            MALIIT_ADDRESS_SERVICE, MALIIT_ADDRESS_PATH,
            DBUS_INTERFACE_PROPERTIES, "Get");
        const char* interfaceName = MALIIT_ADDRESS_INTERFACE;
        const char* propertyName = "address";
        if (!message || !dbus_message_append_args(message,
                                                  DBUS_TYPE_STRING, &interfaceName,
                                                  DBUS_TYPE_STRING, &propertyName,
                                                  DBUS_TYPE_INVALID))
        {
            if (message)
                dbus_message_unref(message);
            dbus_connection_close(session);
            dbus_connection_unref(session);
            Logger::error("Sailfish Maliit address request allocation failed");
            return {};
        }

        DBusMessage* reply = dbus_connection_send_with_reply_and_block(
            session, message, 1500, &error);
        dbus_message_unref(message);
        std::string address;
        if (!reply)
        {
            logDBusError("Sailfish Maliit address request failed", &error);
        }
        else
        {
            DBusMessageIter iter;
            DBusMessageIter variant;
            if (dbus_message_iter_init(reply, &iter) &&
                dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_VARIANT)
            {
                dbus_message_iter_recurse(&iter, &variant);
                if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING)
                {
                    const char* value = nullptr;
                    dbus_message_iter_get_basic(&variant, &value);
                    if (value)
                        address = value;
                }
            }
            dbus_message_unref(reply);
        }
        dbus_connection_close(session);
        dbus_connection_unref(session);
        if (address.empty())
            Logger::error("Sailfish Maliit address response was empty");
        return address;
    }

    void shutdown()
    {
        if (!this->connection)
            return;
        dbus_connection_close(this->connection);
        dbus_connection_unref(this->connection);
        this->connection = nullptr;
        this->active = false;
        this->attributeExtensionRegistered = false;
    }

    bool sendMessage(DBusMessage* message)
    {
        if (!message || !this->connection)
        {
            if (message)
                dbus_message_unref(message);
            return false;
        }
        dbus_message_set_no_reply(message, TRUE);
        const bool sent = dbus_connection_send(this->connection, message, nullptr);
        dbus_message_unref(message);
        return sent;
    }

    bool call(const char* method)
    {
        return this->sendMessage(dbus_message_new_method_call(
            nullptr, MALIIT_SERVER_PATH, MALIIT_SERVER_INTERFACE, method));
    }

    bool callWithIntString(const char* method, dbus_int32_t integer, const char* text)
    {
        DBusMessage* message = dbus_message_new_method_call(
            nullptr, MALIIT_SERVER_PATH, MALIIT_SERVER_INTERFACE, method);
        if (!message || !dbus_message_append_args(message,
                                                  DBUS_TYPE_INT32, &integer,
                                                  DBUS_TYPE_STRING, &text,
                                                  DBUS_TYPE_INVALID))
        {
            if (message)
                dbus_message_unref(message);
            return false;
        }
        return this->sendMessage(message);
    }

    void sendWidgetInformation(bool focused, bool focusChanged)
    {
        if (!this->connection)
            return;
        DBusMessage* message = dbus_message_new_method_call(
            nullptr, MALIIT_SERVER_PATH, MALIIT_SERVER_INTERFACE,
            "updateWidgetInformation");
        if (!message)
            return;

        DBusMessageIter args;
        DBusMessageIter map;
        dbus_message_iter_init_append(message, &args);
        if (!dbus_message_iter_open_container(&args, DBUS_TYPE_ARRAY, "{sv}", &map))
        {
            dbus_message_unref(message);
            return;
        }

        dbus_bool_t focusState = focused;
        dbus_int32_t contentType = this->numberInput ? 1 : 0;
        std::string surrounding = GLFWImeManager::getInputText();
        const char* surroundingValue = surrounding.c_str();
        dbus_int32_t cursorPosition = GLFWImeManager::cursor < 0
                                           ? static_cast<dbus_int32_t>(GLFWImeManager::textBuffer.size())
                                           : std::min<dbus_int32_t>(GLFWImeManager::cursor,
                                                                    GLFWImeManager::textBuffer.size());
        dbus_int32_t anchorPosition = cursorPosition;
        dbus_bool_t hasSelection = FALSE;
        dbus_bool_t predictionEnabled = this->numberInput ? FALSE : TRUE;
        dbus_bool_t autocapitalizationEnabled = this->numberInput ? FALSE : TRUE;
        dbus_bool_t hiddenText = FALSE;
        dbus_bool_t focusChangedValue = focusChanged;
        dbus_int32_t enterKeyType = 2; // Qt::EnterKeyDone

        bool ok = appendVariant(&map, "focusState", DBUS_TYPE_BOOLEAN,
                                DBUS_TYPE_BOOLEAN_AS_STRING, &focusState) &&
                  appendVariant(&map, "contentType", DBUS_TYPE_INT32,
                                DBUS_TYPE_INT32_AS_STRING, &contentType) &&
                  appendVariant(&map, "surroundingText", DBUS_TYPE_STRING,
                                DBUS_TYPE_STRING_AS_STRING, &surroundingValue) &&
                  appendVariant(&map, "cursorPosition", DBUS_TYPE_INT32,
                                DBUS_TYPE_INT32_AS_STRING, &cursorPosition) &&
                  appendVariant(&map, "anchorPosition", DBUS_TYPE_INT32,
                                DBUS_TYPE_INT32_AS_STRING, &anchorPosition) &&
                  appendVariant(&map, "hasSelection", DBUS_TYPE_BOOLEAN,
                                DBUS_TYPE_BOOLEAN_AS_STRING, &hasSelection) &&
                  appendVariant(&map, "predictionEnabled", DBUS_TYPE_BOOLEAN,
                                DBUS_TYPE_BOOLEAN_AS_STRING, &predictionEnabled) &&
                  appendVariant(&map, "autocapitalizationEnabled", DBUS_TYPE_BOOLEAN,
                                DBUS_TYPE_BOOLEAN_AS_STRING, &autocapitalizationEnabled) &&
                  appendVariant(&map, "hiddenText", DBUS_TYPE_BOOLEAN,
                                DBUS_TYPE_BOOLEAN_AS_STRING, &hiddenText) &&
                  appendVariant(&map, "enterKeyType", DBUS_TYPE_INT32,
                                DBUS_TYPE_INT32_AS_STRING, &enterKeyType);
        if (!ok || !dbus_message_iter_close_container(&args, &map) ||
            !dbus_message_iter_append_basic(&args, DBUS_TYPE_BOOLEAN, &focusChangedValue))
        {
            dbus_message_unref(message);
            Logger::error("Sailfish Maliit widget-state message allocation failed");
            return;
        }
        this->sendMessage(message);
    }

    void replaceText(const std::string& value, int replacementStart,
                     int replacementLength, int requestedCursor)
    {
        if (GLFWImeManager::cursor < 0 ||
            GLFWImeManager::cursor > static_cast<int>(GLFWImeManager::textBuffer.size()))
            GLFWImeManager::cursor = GLFWImeManager::textBuffer.size();
        const int oldCursor = GLFWImeManager::cursor;
        const int start = std::clamp(oldCursor + replacementStart, 0,
                                     static_cast<int>(GLFWImeManager::textBuffer.size()));
        const int length = std::clamp(replacementLength, 0,
                                      static_cast<int>(GLFWImeManager::textBuffer.size()) - start);
        const std::wstring inserted = utf8ToWide(value);
        GLFWImeManager::textBuffer.erase(start, length);
        GLFWImeManager::textBuffer.insert(start, inserted);
        GLFWImeManager::cursor = requestedCursor >= 0
                     ? std::clamp(oldCursor + replacementStart + requestedCursor, 0,
                                  static_cast<int>(GLFWImeManager::textBuffer.size()))
                     : start + inserted.size();
        GLFWImeManager::preeditTextBuffer.clear();
        this->preeditReplacementStart = 0;
        this->preeditReplacementLength = 0;
        GLFWImeManager::isEditing = false;
        this->updateState();
    }

    void eraseBackward()
    {
        if (!GLFWImeManager::preeditTextBuffer.empty())
        {
            GLFWImeManager::preeditTextBuffer.clear();
            GLFWImeManager::isEditing = false;
            return;
        }
        if (GLFWImeManager::cursor < 0 ||
            GLFWImeManager::cursor > static_cast<int>(GLFWImeManager::textBuffer.size()))
            GLFWImeManager::cursor = GLFWImeManager::textBuffer.size();
        if (GLFWImeManager::cursor > 0)
        {
            GLFWImeManager::textBuffer.erase(GLFWImeManager::cursor - 1, 1);
            --GLFWImeManager::cursor;
            this->updateState();
        }
    }

    DBusHandlerResult handleMessage(DBusConnection* callbackConnection, DBusMessage* message)
    {
        if (dbus_message_is_method_call(message, MALIIT_CLIENT_INTERFACE, "commitString"))
        {
            DBusError error;
            dbus_error_init(&error);
            const char* text = "";
            dbus_int32_t replacementStart = 0;
            dbus_int32_t replacementLength = 0;
            dbus_int32_t requestedCursor = -1;
            if (dbus_message_get_args(message, &error,
                                      DBUS_TYPE_STRING, &text,
                                      DBUS_TYPE_INT32, &replacementStart,
                                      DBUS_TYPE_INT32, &replacementLength,
                                      DBUS_TYPE_INT32, &requestedCursor,
                                      DBUS_TYPE_INVALID))
            {
                this->replaceText(text ? text : "", replacementStart,
                                  replacementLength, requestedCursor);
            }
            else
                logDBusError("Sailfish Maliit commitString decode failed", &error);
            this->sendEmptyReply(callbackConnection, message);
            return DBUS_HANDLER_RESULT_HANDLED;
        }

        if (dbus_message_is_method_call(message, MALIIT_CLIENT_INTERFACE, "updatePreedit"))
        {
            DBusMessageIter iter;
            const char* text = "";
            dbus_int32_t replacementStart = 0;
            dbus_int32_t replacementLength = 0;
            dbus_int32_t preeditCursor = -1;
            bool valid = dbus_message_iter_init(message, &iter) &&
                         dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_STRING;
            if (valid)
            {
                dbus_message_iter_get_basic(&iter, &text);
                valid = dbus_message_iter_next(&iter) &&
                        dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_ARRAY &&
                        dbus_message_iter_next(&iter) &&
                        dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_INT32;
            }
            if (valid)
            {
                dbus_message_iter_get_basic(&iter, &replacementStart);
                valid = dbus_message_iter_next(&iter) &&
                        dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_INT32;
            }
            if (valid)
            {
                dbus_message_iter_get_basic(&iter, &replacementLength);
                valid = dbus_message_iter_next(&iter) &&
                        dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_INT32;
            }
            if (valid)
            {
                dbus_message_iter_get_basic(&iter, &preeditCursor);
                GLFWImeManager::preeditTextBuffer = text ? text : "";
                this->preeditReplacementStart = replacementStart;
                this->preeditReplacementLength = replacementLength;
                GLFWImeManager::isEditing = !GLFWImeManager::preeditTextBuffer.empty();
            }
            else
                Logger::error("Sailfish Maliit updatePreedit decode failed");
            this->sendEmptyReply(callbackConnection, message);
            return DBUS_HANDLER_RESULT_HANDLED;
        }

        if (dbus_message_is_method_call(message, MALIIT_CLIENT_INTERFACE, "keyEvent"))
        {
            DBusError error;
            dbus_error_init(&error);
            dbus_int32_t type = 0;
            dbus_int32_t key = 0;
            dbus_int32_t modifiers = 0;
            const char* text = "";
            dbus_bool_t autoRepeat = FALSE;
            dbus_int32_t count = 0;
            unsigned char requestType = 0;
            if (dbus_message_get_args(message, &error,
                                      DBUS_TYPE_INT32, &type,
                                      DBUS_TYPE_INT32, &key,
                                      DBUS_TYPE_INT32, &modifiers,
                                      DBUS_TYPE_STRING, &text,
                                      DBUS_TYPE_BOOLEAN, &autoRepeat,
                                      DBUS_TYPE_INT32, &count,
                                      DBUS_TYPE_BYTE, &requestType,
                                      DBUS_TYPE_INVALID))
            {
                constexpr int QT_KEY_PRESS = 6;
                constexpr int QT_KEY_BACKSPACE = 0x01000003;
                constexpr int QT_KEY_RETURN = 0x01000004;
                constexpr int QT_KEY_ENTER = 0x01000005;
                if (type == QT_KEY_PRESS && key == QT_KEY_BACKSPACE)
                    this->eraseBackward();
                else if (type == QT_KEY_PRESS &&
                         (key == QT_KEY_RETURN || key == QT_KEY_ENTER))
                {
                    this->commitPreedit();
                    if (this->owner->activeDialog)
                        this->owner->activeDialog->dismissInput(true);
                }
            }
            else
                logDBusError("Sailfish Maliit keyEvent decode failed", &error);
            this->sendEmptyReply(callbackConnection, message);
            return DBUS_HANDLER_RESULT_HANDLED;
        }

        if (dbus_message_is_method_call(message, MALIIT_CLIENT_INTERFACE, "preeditRectangle"))
        {
            DBusMessage* reply = dbus_message_new_method_return(message);
            dbus_bool_t valid = FALSE;
            dbus_int32_t zero = 0;
            if (reply)
            {
                dbus_message_append_args(reply,
                                         DBUS_TYPE_BOOLEAN, &valid,
                                         DBUS_TYPE_INT32, &zero,
                                         DBUS_TYPE_INT32, &zero,
                                         DBUS_TYPE_INT32, &zero,
                                         DBUS_TYPE_INT32, &zero,
                                         DBUS_TYPE_INVALID);
                dbus_connection_send(callbackConnection, reply, nullptr);
                dbus_message_unref(reply);
            }
            return DBUS_HANDLER_RESULT_HANDLED;
        }

        if (dbus_message_is_method_call(message, MALIIT_CLIENT_INTERFACE, "selection"))
        {
            DBusMessage* reply = dbus_message_new_method_return(message);
            dbus_bool_t valid = FALSE;
            const char* empty = "";
            if (reply)
            {
                dbus_message_append_args(reply,
                                         DBUS_TYPE_BOOLEAN, &valid,
                                         DBUS_TYPE_STRING, &empty,
                                         DBUS_TYPE_INVALID);
                dbus_connection_send(callbackConnection, reply, nullptr);
                dbus_message_unref(reply);
            }
            return DBUS_HANDLER_RESULT_HANDLED;
        }

        if (dbus_message_has_interface(message, MALIIT_CLIENT_INTERFACE))
        {
            this->sendEmptyReply(callbackConnection, message);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

    void sendEmptyReply(DBusConnection* callbackConnection, DBusMessage* message)
    {
        if (dbus_message_get_no_reply(message))
            return;
        DBusMessage* reply = dbus_message_new_method_return(message);
        if (!reply)
            return;
        dbus_connection_send(callbackConnection, reply, nullptr);
        dbus_message_unref(reply);
    }
};
#endif

static size_t encode_utf8(char* s, unsigned int ch)
{
    size_t count = 0;

    if (ch < 0x80)
        s[count++] = (char)ch;
    else if (ch < 0x800)
    {
        s[count++] = (ch >> 6) | 0xc0;
        s[count++] = (ch & 0x3f) | 0x80;
    }
    else if (ch < 0x10000)
    {
        s[count++] = (ch >> 12) | 0xe0;
        s[count++] = ((ch >> 6) & 0x3f) | 0x80;
        s[count++] = (ch & 0x3f) | 0x80;
    }
    else if (ch < 0x110000)
    {
        s[count++] = (ch >> 18) | 0xf0;
        s[count++] = ((ch >> 12) & 0x3f) | 0x80;
        s[count++] = ((ch >> 6) & 0x3f) | 0x80;
        s[count++] = (ch & 0x3f) | 0x80;
    }

    return count;
}

void GLFWImeManager::ime_callback(GLFWwindow* window)
{
    currentIMEStatus = glfwGetInputMode(window, GLFW_IME);
    brls::Logger::info("IME switched: {}", currentIMEStatus ? "ON" : "OFF");
}

void GLFWImeManager::preedit_callback(GLFWwindow* window, int preeditCount,
    unsigned int* preeditString, int blockCount,
    int* blockSizes, int focusedBlock, int caret)
{
    int blockIndex = -1, remainingBlockSize = 0;
    if (preeditCount == 0 || blockCount == 0)
    {
        strcpy(preeditBuf, "(empty)");
        preeditTextBuffer = "";
        return;
    }

    strcpy(preeditBuf, "");

    for (int i = 0; i < preeditCount; i++)
    {
        char encoded[5]     = "";
        size_t encodedCount = 0;

        if (i == caret)
        {
            if (strlen(preeditBuf) < MAX_PREEDIT_LEN)
                strcat(preeditBuf, "");
        }
        if (remainingBlockSize == 0)
        {
            if (blockIndex == focusedBlock)
            {
                if (strlen(preeditBuf) + strlen("]") < MAX_PREEDIT_LEN)
                    strcat(preeditBuf, "]");
            }
            blockIndex++;
            remainingBlockSize = blockSizes[blockIndex];
            if (blockIndex == focusedBlock)
            {
                if (strlen(preeditBuf) + strlen("[") < MAX_PREEDIT_LEN)
                    strcat(preeditBuf, "[");
            }
        }
        encodedCount          = encode_utf8(encoded, preeditString[i]);
        encoded[encodedCount] = '\0';
        if (strlen(preeditBuf) + strlen(encoded) < MAX_PREEDIT_LEN)
            strcat(preeditBuf, encoded);
        remainingBlockSize--;
    }
    if (blockIndex == focusedBlock)
    {
        if (strlen(preeditBuf) + strlen("]") < MAX_PREEDIT_LEN)
            strcat(preeditBuf, "]");
    }
    if (caret == preeditCount)
    {
        if (strlen(preeditBuf) < MAX_PREEDIT_LEN)
            strcat(preeditBuf, "");
    }

    preeditTextBuffer = std::string { preeditBuf };
}

void GLFWImeManager::char_callback(GLFWwindow* window, unsigned int codepoint)
{
    if (!showIME)
        return;
    if (cursor < 0 || cursor > (int)textBuffer.size())
        cursor = textBuffer.size();
    textBuffer.insert(textBuffer.begin() + cursor, (wchar_t)codepoint);
    cursor++;
}

GLFWImeManager::GLFWImeManager(GLFWwindow* window)
    : window(window)
{
    showIME          = false;
    currentIMEStatus = glfwGetInputMode(window, GLFW_IME);
    glfwSetPreeditCursorRectangle(window, 0, 0, 1, 1);
    glfwSetIMEStatusCallback(window, ime_callback);
    glfwSetPreeditCallback(window, preedit_callback);
    glfwSetCharCallback(window, char_callback);
#ifdef SILISILI_SAILFISH_MOBILE
    this->maliitContext = std::make_unique<SailfishMaliitContext>(this);
#endif
}

GLFWImeManager::~GLFWImeManager() = default;

void GLFWImeManager::openInputDialog(std::function<void(std::string)> cb, std::string headerText,
    std::string subText, size_t maxStringLength, std::string initialText, bool numberInput)
{
#ifdef __linux__
    if (isSteamDeck())
    {
        brls::delay(200, []()
            { runSteamDeckCommand("steam://open/keyboard?Mode=0\n"); });
    }
#endif
    preeditTextBuffer.clear();
    showIME     = true;
    textBuffer  = std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(initialText);
    auto dialog = new EditTextDialog();
    dialog->setText(initialText);
    cursor = -1;
    dialog->setCursor(cursor);
    dialog->setHintText(subText);
    dialog->setHeaderText(headerText);
    dialog->setCountText(std::to_string(utf8len(initialText.data())) + "/" + std::to_string(maxStringLength));
#if defined(BOREALIS_USE_D3D11)
    float scale = Application::windowScale;
#else
    float scale = Application::windowScale / Application::getPlatform()->getVideoContext()->getScaleFactor();
#endif
    dialog->getLayoutEvent()->subscribe([this, scale](Point p)
        { glfwSetPreeditCursorRectangle(window, p.x * scale, p.y * scale, 1, 1); });

    dialog->getClipboardEvent()->subscribe([dialog, maxStringLength](const std::string& str)
        {
            if(isEditing || str.empty()) return;
            if (cursor < 0 || cursor > (int)textBuffer.size()) cursor = textBuffer.size();
            auto left = std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(textBuffer.substr(0, cursor));
            auto right = std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(textBuffer.substr(cursor, textBuffer.size()));
            auto clipboard = std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(str);
            textBuffer.insert(textBuffer.begin() + cursor, clipboard.begin(), clipboard.end());
            cursor += clipboard.size();
            if (textBuffer.size() > maxStringLength) {
                textBuffer = textBuffer.substr(0, maxStringLength);
            }
            if (cursor < 0 || cursor > (int)textBuffer.size()) cursor = textBuffer.size();
            dialog->setText(std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(textBuffer));
            dialog->setCursor(cursor); });

    // update
    auto eventID = Application::getRunLoopEvent()->subscribe([this, dialog, maxStringLength]()
        {
#ifdef SILISILI_SAILFISH_MOBILE
            this->maliitContext->dispatch();
#endif
            static std::wstring lastText = textBuffer;
            static std::string lastPreeditText = preeditTextBuffer;
            if(lastText != textBuffer){
                if(textBuffer.size() > maxStringLength)
                    textBuffer.erase(maxStringLength, textBuffer.size() - maxStringLength);
                lastText = textBuffer;
                if(textBuffer.empty()){
                    dialog->setText("");
                } else{
                    dialog->setText(getInputText());
                    dialog->setCursor(cursor);
                }
                dialog->setCountText(std::to_string(textBuffer.size()) + "/" + std::to_string(maxStringLength));
                lastPreeditText.clear();
                preeditTextBuffer.clear();
                isEditing = false;
            } else if(lastPreeditText != preeditTextBuffer){
                lastPreeditText = preeditTextBuffer;
                if (preeditTextBuffer.empty()) {
                    isEditing = false;
                    dialog->setText(getInputText());
                    dialog->setCursor(cursor);
                    dialog->setCountText(std::to_string(textBuffer.size()) + "/" +
                        std::to_string(maxStringLength));
                    return ;
                }
                isEditing = true;
                if (cursor < 0 || cursor > (int)textBuffer.size()) cursor = textBuffer.size();
                auto left = std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(textBuffer.substr(0, cursor));
                auto right = std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(textBuffer.substr(cursor, textBuffer.size()));
                dialog->setText(left + preeditTextBuffer + right);
                dialog->setCursor(cursor + utf8len(preeditTextBuffer.data()));
                dialog->setCountText(std::to_string(textBuffer.size() +
                    utf8len(preeditTextBuffer.data())) + "/" + std::to_string(maxStringLength));
            } });

    // delete text
    dialog->getBackspaceEvent()->subscribe([dialog](...)
        {
            if(textBuffer.empty()) return true;
            if (cursor < 0 || cursor > (int)textBuffer.size()) cursor = textBuffer.size();
            if (cursor > 0 && cursor <= (int)textBuffer.size()) {
                textBuffer.erase(cursor - 1, 1);
                cursor--;
                dialog->setCursor(cursor);
            }
            return true; });

    dialog->registerAction(
        "hints/left"_i18n, BUTTON_LEFT, [dialog](...)
        {
            if (isEditing) return true;
            if (cursor == (int)CursorPosition::END) {
                cursor = textBuffer.empty() ? 0 : (int)textBuffer.size() - 1;
            } else if (cursor > (int)CursorPosition::START) {
                cursor--;
            }
            dialog->setCursor(cursor);
            return true; }, true, true);
    dialog->registerAction(
        "hints/right"_i18n, BUTTON_RIGHT, [dialog](...)
        {
            if (isEditing) return true;
            if (cursor >= (int)CursorPosition::START) {
                if (cursor < (int)textBuffer.size()) {
                    cursor++;
                    dialog->setCursor(cursor);
                }
            }
            return true; }, true, true);

    size_t imeActivationID = 0;
#ifdef SILISILI_SAILFISH_MOBILE
    imeActivationID = brls::delay(120, [this]()
        {
            if (!showIME)
                return;
            glfwSetInputMode(window, GLFW_IME, GLFW_TRUE);
            this->maliitContext->retryShow();
            Logger::info("Sailfish input IME activation retry after dialog open");
        });
#endif

    // cancel
    dialog->getCancelEvent()->subscribe([this, eventID, imeActivationID]()
        {
            if (imeActivationID != 0)
                brls::cancelDelay(imeActivationID);
#ifdef SILISILI_SAILFISH_MOBILE
            this->maliitContext->deactivate();
            this->activeDialog = nullptr;
#endif
            glfwSetInputMode(window, GLFW_IME, GLFW_FALSE);
            Application::getRunLoopEvent()->unsubscribe(eventID);
            showIME = false; });

    // submit
    dialog->getSubmitEvent()->subscribe([this, eventID, imeActivationID, cb]()
        {
            if (imeActivationID != 0)
                brls::cancelDelay(imeActivationID);
#ifdef SILISILI_SAILFISH_MOBILE
            this->maliitContext->commitPreedit();
            this->maliitContext->deactivate();
            this->activeDialog = nullptr;
#endif
            glfwSetInputMode(window, GLFW_IME, GLFW_FALSE);
            Application::getRunLoopEvent()->unsubscribe(eventID);
            showIME = false;
            cb(getInputText());
            return true; });

    dialog->open();
#ifdef SILISILI_SAILFISH_MOBILE
    this->activeDialog = dialog;
    this->maliitContext->activate(numberInput);
#else
    (void)numberInput;
#endif
    glfwSetInputMode(window, GLFW_IME, GLFW_TRUE);
#ifdef SILISILI_SAILFISH_MOBILE
    Logger::info("Sailfish input IME activated after dialog open");
#endif
}

std::string GLFWImeManager::getInputText()
{
    return std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(textBuffer);
}

bool GLFWImeManager::openForText(std::function<void(std::string)> f, std::string headerText,
    std::string subText, int maxStringLength, std::string initialText,
    int kbdDisableBitmask)
{
    this->openInputDialog([f](const std::string& text)
        { f(text); },
        headerText, subText, maxStringLength, initialText, false);
    return true;
}

bool GLFWImeManager::openForNumber(std::function<void(long)> f, std::string headerText,
    std::string subText, int maxStringLength, std::string initialText,
    std::string leftButton, std::string rightButton,
    int kbdDisableBitmask)
{
    this->openInputDialog([f](const std::string& text)
        {
            if(text.empty()) return ;
            try
            {
                f(stoll(text));
            }
            catch (const std::invalid_argument& e)
            {
                Logger::error("Could not parse input, did you enter a valid integer? {}", e.what());
            }
            catch (const std::out_of_range& e) {
                Logger::error("Out of range: {}", e.what());
            }
            catch (const std::exception& e)
            {
                Logger::error("Unexpected error occurred: {}", e.what());
            } },
        headerText, subText, maxStringLength, initialText, true);
    return true;
}

};
