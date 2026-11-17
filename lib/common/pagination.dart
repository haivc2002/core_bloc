import 'dart:async';

import 'package:core_bloc/common/core_scroll_controller.dart';
import 'package:core_bloc/common/core_utils.dart';
import 'package:core_bloc/common/network_catching.dart';
import 'package:core_bloc/network/network_exception.dart';

mixin Pagination<E> on NetworkCatching {
  void add(E event);
  bool get isClosed;

  CoreScrollController? _scrollController;
  Object? _activeRequest;
  E? _refreshEvent;
  Completer<void>? _refreshCompletion;
  bool _isLoadMore = false;
  bool _isMoreEnable = true;
  bool withScrollController = false;

  bool get isMoreEnable => _isMoreEnable;

  set isMoreEnable(bool value) {
    _isMoreEnable = value;
    _scrollController?.isMoreEnable = value;
  }

  bool get isLoadMore => _isLoadMore;

  set isLoadMore(bool value) {
    _isLoadMore = value;
    _scrollController?.isLoadMore = value;
  }

  set setEnableScrollController(bool value) => withScrollController = value;

  /// Tự động khởi tạo lười (lazy) CoreScrollController và gắn listener lắng nghe cuộn
  CoreScrollController get scrollController {
    if (_scrollController == null) {
      _scrollController = CoreScrollController();
      _scrollController!.isMoreEnable = _isMoreEnable;
      _scrollController!.isLoadMore = _isLoadMore;
      _scrollController!.addListener(_scrollListener);
      withScrollController = true;
    }
    return _scrollController!;
  }

  bool get hasScrollController => _scrollController != null;

  void _scrollListener() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;

    if (controller.position.pixels >= controller.position.maxScrollExtent &&
        !controller.position.outOfRange) {
      if (!_isLoadMore && _refreshCompletion == null && isMoreEnable) {
        _isLoadMore = true;
        controller.isLoadMore = true;
        onLoadMore();
      }
    }
  }

  /// Hook được gọi tự động khi người dùng cuộn chạm đáy danh sách
  /// Override hàm này trong BLoC để gọi API trang tiếp theo
  void onLoadMore() {
    coreLog("ENABLE LOAD MORE");
  }

  /// Kết thúc một lượt load more.
  /// [hasMore]: Có còn trang tiếp theo hay không (nếu false sẽ tắt cờ isMoreEnable và ẩn loader)
  void finishLoadMore({bool hasMore = true}) {
    _isLoadMore = false;
    isMoreEnable = hasMore;
    if (_scrollController != null) {
      _scrollController!.isLoadMore = false;
      _scrollController!.isMoreEnable = hasMore;
    }
    coreLog("FINISH LOAD MORE (hasMore: $hasMore)");
  }

  /// Reset lại trạng thái phân trang khi Refresh danh sách từ đầu
  Future<void> onRefresh() async {
    resetPagination();
    coreLog("ENABLE REFRESH");
  }

  /// Dispatches a refresh and completes after its paginated request finishes.
  Future<void> refreshPage(E event) {
    if (isClosed || viewState.isClosed) return Future<void>.value();
    final pending = _refreshCompletion;
    if (pending != null) return pending.future;

    resetPagination();
    coreLog("ENABLE REFRESH");
    final completion = Completer<void>();
    _activeRequest = null;
    _refreshEvent = event;
    _refreshCompletion = completion;
    add(event);
    return completion.future;
  }

  /// Runs one page request and releases the scroll lock when it finishes.
  Future<void> runPaginatedRequest<T>(
    E event, {
    required Future<Result<T>> Function() onAction,
    required void Function(T data) onSuccess,
    void Function(int code, String message, dynamic res)? onFailure,
    LoadingNetworkType loadingType = LoadingNetworkType.normal,
  }) async {
    final request = Object();
    final isRefresh = _refreshCompletion != null &&
        identical(_refreshEvent, event);
    if (_refreshCompletion != null && !isRefresh) return;
    _activeRequest = request;
    bool isCurrentRequest() => identical(_activeRequest, request);

    try {
      await runNetworkCatching<T>(
        onAction: onAction,
        onSuccess: onSuccess,
        onFailure: onFailure,
        loadingType: loadingType,
        shouldHandleResult: isCurrentRequest,
      );
    } finally {
      if (isCurrentRequest()) {
        _activeRequest = null;
        if (isLoadMore) finishLoadMore(hasMore: isMoreEnable);
        if (isRefresh) _completeRefresh();
      }
    }
  }

  void _completeRefresh() {
    _refreshCompletion?.complete();
    _refreshCompletion = null;
    _refreshEvent = null;
  }

  /// Đặt lại các cờ phân trang về trạng thái ban đầu
  void resetPagination() {
    _isLoadMore = false;
    isMoreEnable = true;
    if (_scrollController != null) {
      _scrollController!.isLoadMore = false;
      _scrollController!.isMoreEnable = true;
    }
  }

  /// Dọn dẹp listener và giải phóng ScrollController khi BLoC đóng
  void disposePagination() {
    _activeRequest = null;
    _completeRefresh();
    if (_scrollController != null) {
      _scrollController!.removeListener(_scrollListener);
      _scrollController!.dispose();
      _scrollController = null;
    }
  }
}
