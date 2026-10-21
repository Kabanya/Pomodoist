#include "mvd_windows_taskbar_menu.h"

#include "multi_view_desktop.h"

#include <objidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wincrypt.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <codecvt>
#include <filesystem>
#include <locale>
#include <optional>
#include <string>
#include <vector>

#pragma comment(lib, "Crypt32.lib")
#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "Shell32.lib")
#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "Propsys.lib")
#pragma comment(lib, "windowscodecs.lib")

namespace multi_view_desktop {
namespace {

constexpr wchar_t kTaskbarMenuArgPrefix[] = L"--mvd-taskbar-menu=";
constexpr wchar_t kRunnerWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kHostWindowClassName[] = L"MULTIVIEW_DESKTOP_HOST_WINDOW";
constexpr wchar_t kRegisteredMessageName[] =
    L"MULTIVIEW_DESKTOP_TASKBAR_MENU_SELECT";

struct TaskbarMenuLinkSpec {
  int id = 0;
  std::wstring title;
  std::wstring icon_path;
};

std::optional<int> g_pending_menu_id;
std::vector<TaskbarMenuLinkSpec> g_pending_jump_list_items;
bool g_shell_integration_initialized = false;
std::wstring g_app_user_model_id;

UINT TaskbarMenuMessageId() {
  static const UINT message_id =
      RegisterWindowMessageW(kRegisteredMessageName);
  return message_id;
}

std::wstring GetExecutablePath() {
  std::wstring path(MAX_PATH, L'\0');
  while (true) {
    const DWORD length =
        GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (length < path.size()) {
      path.resize(length);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

std::wstring BuildAppUserModelId() {
  const std::wstring exe_path = GetExecutablePath();
  if (exe_path.empty()) {
    return L"MultiviewDesktop.App";
  }
  const std::wstring filename = std::filesystem::path(exe_path).stem().wstring();
  if (filename.empty()) {
    return L"MultiviewDesktop.App";
  }
  return L"MultiviewDesktop." + filename;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
  return converter.from_bytes(value);
}

std::optional<int> ParseTaskbarMenuArgFromCommandLine() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::nullopt;
  }

  std::optional<int> parsed_id;
  for (int i = 1; i < argc; ++i) {
    const wchar_t* arg = argv[i];
    if (arg == nullptr) {
      continue;
    }
    const size_t prefix_length = wcslen(kTaskbarMenuArgPrefix);
    if (wcsncmp(arg, kTaskbarMenuArgPrefix, prefix_length) != 0) {
      continue;
    }
    const wchar_t* id_text = arg + prefix_length;
    if (id_text[0] == L'\0') {
      continue;
    }
    wchar_t* end = nullptr;
    const long id = wcstol(id_text, &end, 10);
    if (end != id_text && id >= 0) {
      parsed_id = static_cast<int>(id);
      break;
    }
  }

  LocalFree(argv);
  return parsed_id;
}

struct FindWindowData {
  DWORD current_process_id = 0;
  HWND found_window = nullptr;
};

BOOL CALLBACK FindOtherInstanceWindowProc(HWND hwnd, LPARAM lparam) {
  auto* data = reinterpret_cast<FindWindowData*>(lparam);
  if (hwnd == nullptr || !IsWindow(hwnd)) {
    return TRUE;
  }

  DWORD window_process_id = 0;
  GetWindowThreadProcessId(hwnd, &window_process_id);
  if (window_process_id == data->current_process_id) {
    return TRUE;
  }

  wchar_t class_name[256] = {};
  if (GetClassNameW(hwnd, class_name, 256) == 0) {
    return TRUE;
  }

  const bool is_runner =
      wcscmp(class_name, kRunnerWindowClassName) == 0;
  const bool is_host = wcscmp(class_name, kHostWindowClassName) == 0;
  if (!is_runner && !is_host) {
    return TRUE;
  }

  if (is_runner) {
    data->found_window = hwnd;
    return FALSE;
  }

  if (data->found_window == nullptr) {
    data->found_window = hwnd;
  }
  return TRUE;
}

HWND FindOtherInstanceMainWindow() {
  FindWindowData data;
  data.current_process_id = GetCurrentProcessId();
  EnumWindows(FindOtherInstanceWindowProc, reinterpret_cast<LPARAM>(&data));
  return data.found_window;
}

std::wstring TaskbarIconDirectory() {
  wchar_t temp_path[MAX_PATH] = {};
  const DWORD length = GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length >= MAX_PATH) {
    return std::wstring();
  }
  std::filesystem::path directory =
      std::filesystem::path(temp_path) / L"multiview_desktop_taskbar_icons";
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  return directory.wstring();
}

std::vector<uint8_t> Base64Decode(const std::string& input) {
  if (input.empty()) {
    return {};
  }
  DWORD size = 0;
  if (!CryptStringToBinaryA(input.c_str(), 0, CRYPT_STRING_BASE64, nullptr,
                            &size, nullptr, nullptr)) {
    return {};
  }
  std::vector<uint8_t> output(size);
  if (!CryptStringToBinaryA(input.c_str(), 0, CRYPT_STRING_BASE64,
                            output.data(), &size, nullptr, nullptr)) {
    return {};
  }
  output.resize(size);
  return output;
}

bool ReadStreamBytes(IStream* stream, std::vector<uint8_t>* output) {
  if (stream == nullptr || output == nullptr) {
    return false;
  }

  STATSTG stats = {};
  if (FAILED(stream->Stat(&stats, STATFLAG_NONAME))) {
    return false;
  }
  if (stats.cbSize.QuadPart <= 0 ||
      stats.cbSize.QuadPart > static_cast<ULONGLONG>(UINT32_MAX)) {
    return false;
  }

  const ULONG size = static_cast<ULONG>(stats.cbSize.QuadPart);
  output->assign(size, 0);

  LARGE_INTEGER seek = {};
  if (FAILED(stream->Seek(seek, STREAM_SEEK_SET, nullptr))) {
    return false;
  }

  ULONG read = 0;
  if (FAILED(stream->Read(output->data(), size, &read)) || read != size) {
    return false;
  }
  return true;
}

bool EncodeBitmapSourceToPng(IWICImagingFactory* factory,
                             IWICBitmapSource* source,
                             std::vector<uint8_t>* output) {
  if (factory == nullptr || source == nullptr || output == nullptr) {
    return false;
  }

  Microsoft::WRL::ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    return false;
  }

  Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                      &encoder))) {
    return false;
  }
  if (FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return false;
  }

  Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;
  Microsoft::WRL::ComPtr<IPropertyBag2> properties;
  if (FAILED(encoder->CreateNewFrame(&frame, &properties))) {
    return false;
  }
  if (FAILED(frame->Initialize(properties.Get()))) {
    return false;
  }
  if (FAILED(frame->WriteSource(source, nullptr))) {
    return false;
  }
  if (FAILED(frame->Commit())) {
    return false;
  }
  if (FAILED(encoder->Commit())) {
    return false;
  }

  return ReadStreamBytes(stream.Get(), output);
}

bool ScalePngToPngAtSize(const std::vector<uint8_t>& png_bytes,
                         UINT size,
                         std::vector<uint8_t>* output) {
  if (png_bytes.empty() || output == nullptr || size == 0) {
    return false;
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, png_bytes.size());
  if (memory == nullptr) {
    return false;
  }

  void* locked_memory = GlobalLock(memory);
  if (locked_memory == nullptr) {
    GlobalFree(memory);
    return false;
  }
  memcpy(locked_memory, png_bytes.data(), png_bytes.size());
  GlobalUnlock(memory);

  Microsoft::WRL::ComPtr<IStream> png_stream;
  if (FAILED(CreateStreamOnHGlobal(memory, TRUE, &png_stream))) {
    GlobalFree(memory);
    return false;
  }

  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder;
  Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame;
  Microsoft::WRL::ComPtr<IWICBitmapScaler> scaler;
  Microsoft::WRL::ComPtr<IWICFormatConverter> converter;
  bool success = false;

  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    return false;
  }

  do {
    if (FAILED(factory->CreateDecoderFromStream(
            png_stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad,
            &decoder))) {
      break;
    }
    if (FAILED(decoder->GetFrame(0, &frame))) {
      break;
    }
    if (FAILED(factory->CreateBitmapScaler(&scaler))) {
      break;
    }
    if (FAILED(scaler->Initialize(frame.Get(), size, size,
                                  WICBitmapInterpolationModeFant))) {
      break;
    }
    if (FAILED(factory->CreateFormatConverter(&converter))) {
      break;
    }
    if (FAILED(converter->Initialize(
            scaler.Get(), GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone,
            nullptr, 0.0, WICBitmapPaletteTypeCustom))) {
      break;
    }
    success = EncodeBitmapSourceToPng(factory.Get(), converter.Get(), output);
  } while (false);

  return success;
}

bool WriteIcoFromPngBytes(const std::vector<uint8_t>& png_bytes,
                          const std::wstring& ico_path) {
  if (png_bytes.empty()) {
    return false;
  }

  struct IcoImage {
    UINT size = 0;
    std::vector<uint8_t> png_data;
  };

  std::vector<IcoImage> images;
  for (const UINT size : {16u, 32u}) {
    IcoImage image;
    image.size = size;
    if (ScalePngToPngAtSize(png_bytes, size, &image.png_data) &&
        !image.png_data.empty()) {
      images.push_back(std::move(image));
    }
  }
  if (images.empty()) {
    return false;
  }

  std::vector<uint8_t> ico_data;
  ico_data.reserve(6 + images.size() * 16 + 4096);

  auto append_u8 = [&ico_data](uint8_t value) {
    ico_data.push_back(value);
  };
  auto append_u16 = [&ico_data](uint16_t value) {
    ico_data.push_back(static_cast<uint8_t>(value & 0xFF));
    ico_data.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
  };
  auto append_u32 = [&ico_data](uint32_t value) {
    ico_data.push_back(static_cast<uint8_t>(value & 0xFF));
    ico_data.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    ico_data.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
    ico_data.push_back(static_cast<uint8_t>((value >> 24) & 0xFF));
  };
  auto append_bytes = [&ico_data](const void* data, size_t size) {
    const auto* bytes = static_cast<const uint8_t*>(data);
    ico_data.insert(ico_data.end(), bytes, bytes + size);
  };

  append_u16(0);
  append_u16(1);
  append_u16(static_cast<uint16_t>(images.size()));

  const uint32_t header_size =
      6 + static_cast<uint32_t>(images.size()) * 16;
  uint32_t offset = header_size;
  for (const IcoImage& image : images) {
    const uint8_t dimension =
        image.size >= 256 ? 0 : static_cast<uint8_t>(image.size);
    append_u8(dimension);
    append_u8(dimension);
    append_u8(0);
    append_u8(0);
    append_u16(1);
    append_u16(0);
    append_u32(static_cast<uint32_t>(image.png_data.size()));
    append_u32(offset);
    offset += static_cast<uint32_t>(image.png_data.size());
  }

  for (const IcoImage& image : images) {
    append_bytes(image.png_data.data(), image.png_data.size());
  }

  FILE* file = nullptr;
  if (_wfopen_s(&file, ico_path.c_str(), L"wb") != 0 || file == nullptr) {
    return false;
  }
  const size_t written = fwrite(ico_data.data(), 1, ico_data.size(), file);
  fclose(file);
  return written == ico_data.size();
}

std::wstring NormalizeAbsolutePath(const std::wstring& path) {
  if (path.empty()) {
    return std::wstring();
  }

  wchar_t buffer[MAX_PATH] = {};
  const DWORD length =
      GetFullPathNameW(path.c_str(), MAX_PATH, buffer, nullptr);
  if (length == 0 || length >= MAX_PATH) {
    return path;
  }
  return std::wstring(buffer);
}

std::wstring SaveTaskbarIconFromBase64(int item_id,
                                       const std::string& icon_base64) {
  const std::vector<uint8_t> png_bytes = Base64Decode(icon_base64);
  if (png_bytes.empty()) {
    return std::wstring();
  }

  const std::wstring directory = TaskbarIconDirectory();
  if (directory.empty()) {
    return std::wstring();
  }

  const std::wstring ico_path =
      directory + L"\\menu_" + std::to_wstring(item_id) + L".ico";
  if (!WriteIcoFromPngBytes(png_bytes, ico_path)) {
    return std::wstring();
  }
  return NormalizeAbsolutePath(ico_path);
}

Microsoft::WRL::ComPtr<IShellLinkW> CreateTaskShellLink(
    const std::wstring& exe_path,
    const std::wstring& arguments,
    const std::wstring& title,
    const std::wstring& icon_path) {
  Microsoft::WRL::ComPtr<IShellLinkW> shell_link;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&shell_link)))) {
    return nullptr;
  }

  std::wstring working_directory = exe_path;
  if (!working_directory.empty()) {
    std::vector<wchar_t> mutable_directory(working_directory.begin(),
                                           working_directory.end());
    mutable_directory.push_back(L'\0');
    if (PathRemoveFileSpecW(mutable_directory.data())) {
      shell_link->SetWorkingDirectory(mutable_directory.data());
    }
  }

  shell_link->SetPath(exe_path.c_str());
  shell_link->SetArguments(arguments.c_str());
  shell_link->SetDescription(title.c_str());
  shell_link->SetShowCmd(SW_SHOWNORMAL);
  if (!icon_path.empty()) {
    const std::wstring absolute_icon_path = NormalizeAbsolutePath(icon_path);
    shell_link->SetIconLocation(absolute_icon_path.c_str(), 0);
  }

  Microsoft::WRL::ComPtr<IPropertyStore> property_store;
  if (SUCCEEDED(shell_link.As(&property_store))) {
    PROPVARIANT title_value;
    if (SUCCEEDED(InitPropVariantFromString(title.c_str(), &title_value))) {
      property_store->SetValue(PKEY_Title, title_value);
      PropVariantClear(&title_value);
    }
  }

  return shell_link;
}

bool InstallJumpListFromSpecs(const std::vector<TaskbarMenuLinkSpec>& specs) {
  const std::wstring exe_path = GetExecutablePath();
  if (exe_path.empty()) {
    return false;
  }

  std::vector<Microsoft::WRL::ComPtr<IShellLinkW>> links;
  links.reserve(specs.size());
  for (const TaskbarMenuLinkSpec& spec : specs) {
    if (spec.title.empty()) {
      continue;
    }
    const std::wstring arguments =
        std::wstring(kTaskbarMenuArgPrefix) + std::to_wstring(spec.id);
    auto shell_link =
        CreateTaskShellLink(exe_path, arguments, spec.title, spec.icon_path);
    if (shell_link != nullptr) {
      links.push_back(std::move(shell_link));
    }
  }

  Microsoft::WRL::ComPtr<ICustomDestinationList> destination_list;
  if (FAILED(CoCreateInstance(CLSID_DestinationList, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&destination_list)))) {
    return false;
  }

  if (!g_app_user_model_id.empty()) {
    destination_list->SetAppID(g_app_user_model_id.c_str());
  }

  UINT min_slots = 0;
  Microsoft::WRL::ComPtr<IObjectArray> removed;
  if (FAILED(destination_list->BeginList(&min_slots, IID_PPV_ARGS(&removed)))) {
    return false;
  }

  if (links.empty()) {
    destination_list->DeleteList(nullptr);
    return SUCCEEDED(destination_list->CommitList());
  }

  Microsoft::WRL::ComPtr<IObjectCollection> collection;
  if (FAILED(CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                                CLSCTX_INPROC, IID_PPV_ARGS(&collection)))) {
    destination_list->AbortList();
    return false;
  }

  for (const auto& link : links) {
    collection->AddObject(link.Get());
  }

  if (FAILED(destination_list->AddUserTasks(collection.Get()))) {
    destination_list->AbortList();
    return false;
  }

  return SUCCEEDED(destination_list->CommitList());
}

const flutter::EncodableMap* AsMap(const flutter::EncodableValue& value) {
  return std::get_if<flutter::EncodableMap>(&value);
}

const flutter::EncodableList* AsList(const flutter::EncodableValue& value) {
  return std::get_if<flutter::EncodableList>(&value);
}

std::optional<int> IntFromEncodable(const flutter::EncodableValue& value) {
  if (const auto* int32_value = std::get_if<int32_t>(&value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(&value)) {
    return static_cast<int>(*int64_value);
  }
  return std::nullopt;
}

std::string StringFromEncodable(const flutter::EncodableValue& value) {
  if (const auto* string_value = std::get_if<std::string>(&value)) {
    return *string_value;
  }
  return std::string();
}

void ApplyAppUserModelIdToWindow(HWND hwnd) {
  if (hwnd == nullptr || g_app_user_model_id.empty()) {
    return;
  }

  Microsoft::WRL::ComPtr<IPropertyStore> property_store;
  if (FAILED(SHGetPropertyStoreForWindow(hwnd, IID_PPV_ARGS(&property_store)))) {
    return;
  }

  PROPVARIANT app_id_value;
  if (SUCCEEDED(InitPropVariantFromString(g_app_user_model_id.c_str(),
                                          &app_id_value))) {
    property_store->SetValue(PKEY_AppUserModel_ID, app_id_value);
    PropVariantClear(&app_id_value);
  }
}

std::vector<TaskbarMenuLinkSpec> ParseJumpListItems(
    const flutter::EncodableValue* items_value) {
  std::vector<TaskbarMenuLinkSpec> specs;
  const flutter::EncodableList* items = items_value != nullptr
                                            ? AsList(*items_value)
                                            : nullptr;
  if (items == nullptr) {
    return specs;
  }

  specs.reserve(items->size());
  for (const auto& item_value : *items) {
    const flutter::EncodableMap* item = AsMap(item_value);
    if (item == nullptr) {
      continue;
    }

    const auto id_it = item->find(flutter::EncodableValue("id"));
    const auto title_it = item->find(flutter::EncodableValue("title"));
    if (id_it == item->end() || title_it == item->end()) {
      continue;
    }

    const std::optional<int> item_id = IntFromEncodable(id_it->second);
    const std::string title = StringFromEncodable(title_it->second);
    if (!item_id.has_value() || title.empty()) {
      continue;
    }

    TaskbarMenuLinkSpec spec;
    spec.id = *item_id;
    spec.title = Utf8ToWide(title);

    const auto icon_it = item->find(flutter::EncodableValue("icon"));
    if (icon_it != item->end()) {
      const std::string icon_base64 = StringFromEncodable(icon_it->second);
      if (!icon_base64.empty()) {
        spec.icon_path = SaveTaskbarIconFromBase64(spec.id, icon_base64);
      }
    }

    specs.push_back(std::move(spec));
  }

  return specs;
}

void InstallPendingJumpList() {
  InstallJumpListFromSpecs(g_pending_jump_list_items);
}

void QueueJumpListInstall(const flutter::EncodableValue* items_value) {
  g_pending_jump_list_items = ParseJumpListItems(items_value);
  InstallPendingJumpList();
}

}  // namespace

void MvdWindowsInitializeShellIntegration() {
  if (g_shell_integration_initialized) {
    return;
  }

  if (g_app_user_model_id.empty()) {
    g_app_user_model_id = BuildAppUserModelId();
  }

  SetCurrentProcessExplicitAppUserModelID(g_app_user_model_id.c_str());
  g_shell_integration_initialized = true;
}

bool MvdWindowsTryForwardTaskbarMenuActivation() {
  MvdWindowsInitializeShellIntegration();

  const std::optional<int> menu_id = ParseTaskbarMenuArgFromCommandLine();
  if (!menu_id.has_value()) {
    return false;
  }

  HWND target_window = FindOtherInstanceMainWindow();
  if (target_window != nullptr) {
    SendMessage(target_window, TaskbarMenuMessageId(),
                static_cast<WPARAM>(*menu_id), 0);
    return true;
  }

  g_pending_menu_id = menu_id;
  return false;
}

void MvdWindowsSetTaskbarMenu(const flutter::EncodableValue* items_value) {
  MvdWindowsInitializeShellIntegration();
  QueueJumpListInstall(items_value);
}

void MvdWindowsFlushPendingTaskbarMenuSelection() {
  if (!g_pending_menu_id.has_value()) {
    return;
  }
  MultiViewDesktop::Instance().EmitTaskbarMenuItemSelected(*g_pending_menu_id);
  g_pending_menu_id.reset();
}

bool MvdWindowsHandleTaskbarMenuMessage(UINT message, WPARAM wparam, LPARAM) {
  if (message != TaskbarMenuMessageId()) {
    return false;
  }

  MultiViewDesktop::Instance().EmitTaskbarMenuItemSelected(
      static_cast<int>(wparam));
  return true;
}

void MvdWindowsApplyAppUserModelIdToWindow(HWND hwnd) {
  MvdWindowsInitializeShellIntegration();
  ApplyAppUserModelIdToWindow(hwnd);
}

}  // namespace multi_view_desktop
