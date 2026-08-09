import 'dart:js_interop';

@JS('pomodoistSetLoadingStage')
external void _setLoadingStage(JSString stage);

@JS('pomodoistHideLoading')
external void _hideLoading();

@JS('pomodoistShowLoadingFailure')
external void _showLoadingFailure();

void updateWebBootstrapStage(String stage) {
  _setLoadingStage(stage.toJS);
}

void hideWebBootstrapLoader() {
  _hideLoading();
}

void showWebBootstrapFailure() {
  _showLoadingFailure();
}
