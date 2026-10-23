#include "mvd_linux_pomo_popup.h"
#include <gtk-layer-shell.h>

namespace {
constexpr char kState[] = "mvd-pomo-child-popup";
struct Popup {
  GtkWindow* window = nullptr;
  GtkWindow* parent = nullptr;  // Weak; transient-for owns GTK's relationship.
  GdkSeat* seat = nullptr;
  GdkRectangle source{}, desired{}, actual{};
  bool actual_ready = false;
  bool has_bounds = false;
  bool gtk_grab = false, seat_grab = false;
  bool hiding = false, closing = false, destroying = false;
};
Popup* State(GtkWindow* window) {
  return window && GTK_IS_WINDOW(window)
      ? static_cast<Popup*>(g_object_get_data(G_OBJECT(window), kState)) : nullptr;
}
void Release(Popup* popup) {
  // Remove GTK's modal event redirection before releasing the native seat. A
  // hidden entry must not remain the keyboard focus widget of the popup.
  gtk_window_set_focus(popup->window, nullptr);
  if (popup->gtk_grab) {
    popup->gtk_grab = false;
    gtk_grab_remove(GTK_WIDGET(popup->window));
  }
  if (popup->seat_grab) {
    popup->seat_grab = false;
    gdk_seat_ungrab(popup->seat);
  }
  g_clear_object(&popup->seat);
}
void Position(Popup* popup) {
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(popup->window));
  if (!window || !popup->has_bounds) return;
  // move_to_rect is also the gtk-layer-shell hook which establishes the custom
  // xdg_popup parent; gtk_window_move alone falls back to an ordinary toplevel.
  const GdkRectangle anchor{0, 0, 1, 1};
  gdk_window_move_to_rect(window, &anchor, GDK_GRAVITY_NORTH_WEST,
      GDK_GRAVITY_NORTH_WEST,
      static_cast<GdkAnchorHints>(GDK_ANCHOR_FLIP_X | GDK_ANCHOR_FLIP_Y |
          GDK_ANCHOR_SLIDE_X | GDK_ANCHOR_SLIDE_Y),
      popup->desired.x - popup->source.x,
      popup->desired.y - popup->source.y);
}
void MovedToRect(GdkWindow* window, const GdkRectangle*,
    const GdkRectangle* final_rect, gboolean, gboolean, gpointer data) {
  Popup* popup = State(GTK_WINDOW(data));
  if (!popup || !popup->has_bounds) return;
  GdkRectangle result{};
  if (final_rect) {
    result = *final_rect;
  } else {
    // GtkLayerShell emits null rectangles after applying xdg_popup.configure
    // to the GdkWindow; those coordinates are relative to its parent surface.
    gdk_window_get_geometry(window, &result.x, &result.y,
        &result.width, &result.height);
  }
  if (result.width <= 0 || result.height <= 0) return;
  result.x += popup->source.x;
  result.y += popup->source.y;
  popup->actual = result;
  popup->actual_ready = true;
}
void Realized(GtkWidget* widget, gpointer) {
  g_signal_connect_object(gtk_widget_get_window(widget), "moved-to-rect",
      G_CALLBACK(MovedToRect), widget, static_cast<GConnectFlags>(0));
}
void RequestClose(Popup* popup) {
  if (popup->closing || popup->destroying) return;
  popup->closing = true;
  // Callers receive their normal prevent-close/delete-event lifecycle, after
  // both grabs are gone. The caller may hide again or destroy the window.
  GtkWidget* widget = GTK_WIDGET(g_object_ref(popup->window));
  mvd_linux_pomo_popup_hide(popup->window);
  GdkEvent* event = gdk_event_new(GDK_DELETE);
  if (GdkWindow* window = gtk_widget_get_window(widget)) {
    event->any.window = GDK_WINDOW(g_object_ref(window));
  }
  event->any.send_event = TRUE;
  gboolean handled = FALSE;
  g_signal_emit_by_name(widget, "delete-event", event, &handled);
  gdk_event_free(event);
  if (!handled) gtk_widget_destroy(widget);
  popup->closing = false;
  g_object_unref(widget);
}
void PopupInput(GtkWindow* window, const GdkEvent* event, gpointer data) {
  auto* popup = static_cast<Popup*>(data);
  if (!gtk_widget_get_visible(GTK_WIDGET(window))) return;
  if (event->type == GDK_KEY_PRESS) {
    if (event->key.keyval == GDK_KEY_Escape) RequestClose(popup);
    return;
  }
  if (event->type != GDK_BUTTON_PRESS && event->type != GDK_TOUCH_BEGIN) return;
  GdkWindow* target = gtk_widget_get_window(GTK_WIDGET(window));
  GdkWindow* origin = gdk_event_get_window(event);
  if (!target || !origin) return;
  if (gdk_window_get_toplevel(origin) != target) {
    RequestClose(popup);
    return;
  }
  double x = 0, y = 0;
  if (!gdk_event_get_coords(event, &x, &y)) return;
  // Child FlView event boxes own the event coordinates. Translate only within
  // this native popup; other toplevels are outside without inventing globals.
  for (GdkWindow* child = origin; child && child != target;
       child = gdk_window_get_effective_parent(child)) {
    int dx = 0, dy = 0;
    gdk_window_get_position(child, &dx, &dy);
    x += dx; y += dy;
  }
  GtkAllocation allocation{};
  gtk_widget_get_allocation(GTK_WIDGET(window), &allocation);
  if (x < 0 || y < 0 || x >= allocation.width || y >= allocation.height)
    RequestClose(popup);
}
gboolean GrabBroken(GtkWidget*, GdkEventGrabBroken*, gpointer data) {
  auto* popup = static_cast<Popup*>(data);
  if (popup->gtk_grab || popup->seat_grab) RequestClose(popup);
  return FALSE;
}
void Hidden(GtkWidget*, gpointer data) {
  auto* popup = static_cast<Popup*>(data);
  const bool notify = !popup->hiding && !popup->destroying &&
      (popup->gtk_grab || popup->seat_grab);
  Release(popup);
  if (notify) RequestClose(popup);
}
void Destroyed(GtkWidget*, gpointer data) {
  auto* popup = static_cast<Popup*>(data);
  popup->destroying = true;
  Release(popup);
}
void ParentGone(GtkWidget*, gpointer data) {
  auto* window = GTK_WINDOW(data);
  if (Popup* popup = State(window)) {
    if (gtk_widget_get_visible(GTK_WIDGET(window))) RequestClose(popup);
    else Release(popup);
  }
}
void Prepare(GdkSeat*, GdkWindow*, gpointer data) {
  gtk_widget_show_all(GTK_WIDGET(data));
}
bool IsTrigger(const GdkEvent* event) {
  if (!event) return false;
  switch (event->type) {
    case GDK_BUTTON_PRESS: case GDK_BUTTON_RELEASE:
    case GDK_KEY_PRESS: case GDK_KEY_RELEASE:
    case GDK_TOUCH_BEGIN: case GDK_TOUCH_END:
      return true;
    default: return false;
  }
}
constexpr char kWatch[] = "mvd-pomo-input-watch";
struct InputWatch {
  GtkWindow* window = nullptr;
  GtkGesture* pointer = nullptr;
  GtkEventController* keyboard = nullptr;
  MvdPomoPopupTriggerObserver observer = nullptr;
  gpointer data = nullptr;
};
void Observe(InputWatch* watch, const GdkEvent* event) {
  if (watch->observer && IsTrigger(event))
    watch->observer(watch->window, event, watch->data);
}
void PointerPressed(GtkGestureMultiPress* gesture, gint, gdouble, gdouble,
    gpointer data) {
  GtkGesture* base = GTK_GESTURE(gesture);
  Observe(static_cast<InputWatch*>(data), gtk_gesture_get_last_event(base,
      gtk_gesture_get_last_updated_sequence(base)));
  // Observe only: never claim a sequence or prevent Flutter's own recognizers.
}
gboolean KeyPressed(GtkEventControllerKey*, guint, guint, GdkModifierType,
    gpointer data) {
  GdkEvent* event = gtk_get_current_event();
  Observe(static_cast<InputWatch*>(data), event);
  if (event) gdk_event_free(event);
  return FALSE;
}
}  // namespace

GtkWindow* mvd_linux_pomo_popup_new(GtkWindow* parent) {
  if (!parent || !GTK_IS_WINDOW(parent)) return nullptr;
  auto* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_POPUP));
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_POPUP_MENU);
  gtk_window_set_transient_for(window, parent);
  gtk_window_set_destroy_with_parent(window, TRUE);
  gtk_window_set_decorated(window, FALSE);
  auto* popup = new Popup;
  popup->window = window;
  popup->parent = parent;
  g_object_add_weak_pointer(G_OBJECT(parent),
      reinterpret_cast<gpointer*>(&popup->parent));
  g_object_set_data_full(G_OBJECT(window), kState, popup, +[](gpointer data) {
    auto* value = static_cast<Popup*>(data);
    if (value->parent) g_object_remove_weak_pointer(G_OBJECT(value->parent),
        reinterpret_cast<gpointer*>(&value->parent));
    g_clear_object(&value->seat);
    delete value;
  });
  gtk_widget_add_events(GTK_WIDGET(window), GDK_BUTTON_PRESS_MASK | GDK_KEY_PRESS_MASK);
  g_signal_connect(window, "realize", G_CALLBACK(Realized), nullptr);
  mvd_linux_pomo_popup_watch(window, PopupInput, popup);
  g_signal_connect(window, "grab-broken-event", G_CALLBACK(GrabBroken), popup);
  g_signal_connect(window, "hide", G_CALLBACK(Hidden), popup);
  g_signal_connect(window, "unmap", G_CALLBACK(Hidden), popup);
  g_signal_connect(window, "destroy", G_CALLBACK(Destroyed), popup);
  const char* parent_signals[] = {"hide", "unmap", "destroy"};
  for (const char* signal : parent_signals) {
    g_signal_connect_object(parent, signal, G_CALLBACK(ParentGone), window,
        static_cast<GConnectFlags>(0));
  }
  return window;
}
gboolean mvd_linux_pomo_popup_is(GtkWindow* window) { return State(window) != nullptr; }
void mvd_linux_pomo_popup_move(GtkWindow* window,
    const GdkRectangle* parent_bounds, const GdkRectangle* desired_bounds) {
  Popup* popup = State(window);
  if (!popup || !parent_bounds || !desired_bounds || desired_bounds->width <= 0 ||
      desired_bounds->height <= 0) return;
  popup->source = *parent_bounds;
  popup->desired = *desired_bounds;
  popup->has_bounds = true;
  popup->actual_ready = false;
  gtk_window_resize(window, desired_bounds->width, desired_bounds->height);
  Position(popup);
}
gboolean mvd_linux_pomo_popup_show(GtkWindow* window, const GdkEvent* trigger) {
  Popup* popup = State(window);
  if (!popup || !popup->parent || popup->destroying || !popup->has_bounds ||
      !gtk_widget_get_mapped(GTK_WIDGET(popup->parent)) ||
      !gtk_layer_is_layer_window(popup->parent) || !IsTrigger(trigger)) return FALSE;
  if (gtk_widget_get_visible(GTK_WIDGET(window))) return TRUE;
  GdkDevice* device = gdk_event_get_device(trigger);
  GdkWindow* trigger_window = gdk_event_get_window(trigger);
  if (!device || !trigger_window || gdk_device_get_display(device) !=
      gtk_widget_get_display(GTK_WIDGET(popup->parent)) ||
      gdk_window_get_toplevel(trigger_window) !=
      gtk_widget_get_window(GTK_WIDGET(popup->parent))) return FALSE;
  GdkSeat* seat = gdk_device_get_seat(device);
  if (!seat) return FALSE;
  gtk_widget_realize(GTK_WIDGET(window));
  Position(popup);
  popup->seat = GDK_SEAT(g_object_ref(seat));
  const GdkGrabStatus status = gdk_seat_grab(seat,
      gtk_widget_get_window(GTK_WIDGET(window)),
      static_cast<GdkSeatCapabilities>(GDK_SEAT_CAPABILITY_ALL_POINTING |
          GDK_SEAT_CAPABILITY_KEYBOARD), TRUE, nullptr, trigger, Prepare, window);
  popup->seat_grab = status == GDK_GRAB_SUCCESS;
  if (status != GDK_GRAB_SUCCESS ||
      !gtk_widget_get_mapped(GTK_WIDGET(window))) {
    mvd_linux_pomo_popup_hide(window);
    return FALSE;
  }
  gtk_grab_add(GTK_WIDGET(window));
  popup->gtk_grab = true;
  return TRUE;
}
void mvd_linux_pomo_popup_hide(GtkWindow* window) {
  Popup* popup = State(window);
  if (!popup || popup->hiding) return;
  popup->hiding = true;
  Release(popup);
  gtk_widget_hide(GTK_WIDGET(window));
  popup->hiding = false;
}
gboolean mvd_linux_pomo_popup_bounds(GtkWindow* window, GdkRectangle* bounds) {
  Popup* popup = State(window);
  if (!popup || !popup->has_bounds || !bounds) return FALSE;
  // GTK Layer Shell stores new anchors without repositioning a mapped GTK3
  // popup. Read the actual mapped surface instead of reporting a pending move
  // as completed; this also reflects a resize before another configure signal.
  if (gtk_widget_get_mapped(GTK_WIDGET(window))) {
    GdkRectangle current{};
    gdk_window_get_geometry(gtk_widget_get_window(GTK_WIDGET(window)),
        &current.x, &current.y, &current.width, &current.height);
    if (current.width > 0 && current.height > 0) {
      current.x += popup->source.x;
      current.y += popup->source.y;
      popup->actual = current;
      popup->actual_ready = true;
    }
  }
  *bounds = popup->actual_ready ? popup->actual : popup->desired;
  return TRUE;
}

void mvd_linux_pomo_popup_watch(GtkWindow* window,
    MvdPomoPopupTriggerObserver observer, gpointer data) {
  if (!window || !GTK_IS_WINDOW(window)) return;
  auto* watch = static_cast<InputWatch*>(g_object_get_data(G_OBJECT(window), kWatch));
  if (!watch) {
    watch = new InputWatch;
    watch->window = window;
    watch->pointer = gtk_gesture_multi_press_new(GTK_WIDGET(window));
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(watch->pointer), 0);
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(watch->pointer),
        GTK_PHASE_CAPTURE);
    g_signal_connect(watch->pointer, "pressed", G_CALLBACK(PointerPressed), watch);
    watch->keyboard = gtk_event_controller_key_new(GTK_WIDGET(window));
    gtk_event_controller_set_propagation_phase(watch->keyboard, GTK_PHASE_CAPTURE);
    g_signal_connect(watch->keyboard, "key-pressed", G_CALLBACK(KeyPressed), watch);
    g_object_set_data_full(G_OBJECT(window), kWatch, watch, +[](gpointer value) {
      auto* owned = static_cast<InputWatch*>(value);
      owned->observer = nullptr;
      g_clear_object(&owned->pointer);
      g_clear_object(&owned->keyboard);
      delete owned;
    });
  }
  watch->observer = observer;
  watch->data = data;
}
