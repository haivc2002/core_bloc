# core_bloc · Rule cho agent

Áp dụng từ gốc app Flutter dùng `core_bloc`. Lấy nghiệp vụ và hợp đồng API từ dự án đích. Tra chữ ký trong phiên bản core đang dùng.

## Khởi tạo

- Đặt `core_bloc/` cạnh `pubspec.yaml`, copy `core_bloc/Makefile` ra gốc app. Dependencies gồm `flutter`, `flutter_localizations` (Flutter SDK), `core_bloc: {path: core_bloc}`, `freezed_annotation: ^3.1.0`, `injectable: ^3.0.0`. Dev dependencies gồm `flutter_test` (Flutter SDK), `build_runner: ^2.16.0`, `freezed: any`, `injectable_generator: ^3.1.3`. Kiểm tra `core_bloc/pubspec.yaml` để chọn bộ version tương thích rồi chạy `flutter pub get`. Giữ lint của app. Thêm `go_router_builder` hoặc `riverpod_generator` khi app dùng chúng.
- Tạo `lib/module/network_module.dart` với `static final NetworkService instance = NetworkService(baseUrl: ...)` trong `NetworkModule`. Dùng base URL theo môi trường. Cấu hình `NetworkAuthConfig` nếu có auth. Endpoint cần token dùng `withToken: true`.
- Từ gốc app chạy `make module <feature>`. Scaffold tạo feature, `lib/dependence/injection.dart` nếu thiếu, tạo hoặc cập nhật `lib/router/app_router.dart`, sinh DI và Freezed. Kiểm tra log và file sinh. Các feature sau dùng chung bootstrap.
- Trong `main.dart`, import `core_bloc.dart`, `flutter_localizations.dart`, DI và router của app. Gọi `WidgetsFlutterBinding.ensureInitialized()` → `Dependencies.initialized()` → `await Storage.initialized()` nếu dùng → khởi tạo registry đã sinh nếu dùng → `runApp`.
- `MaterialApp` dùng `navigatorKey: coreNavigatorKey`, `onGenerateRoute: AppRouter.generateRoute`, `initialRoute: AppRouter.<route>`. Đăng ký `CoreLocalizations.delegate` và `.delegate` của `GlobalMaterialLocalizations`, `GlobalWidgetsLocalizations`, `GlobalCupertinoLocalizations`. Đặt `supportedLocales` và `locale` theo app, ví dụ hỗ trợ `vi` và `en`, mặc định `vi`.

## Triển khai feature

Mỗi feature sở hữu event, state, repository, model và entity. Giao tiếp giữa feature qua route, `FeatureAccess` hoặc hợp đồng dùng chung. Dùng scaffold trong `lib/feature/<feature>/`, giữ tên file, lớp và annotation.

1. **Xác định yêu cầu** · Chốt hành động, tham số, method/endpoint, response, token, dữ liệu UI và hành vi lỗi. Xác nhận phần thiếu của hợp đồng thay vì tự đặt endpoint hoặc JSON.
2. **Data** · `data/datasource/<feature>_remote.dart` gọi `NetworkModule.instance` với endpoint, query/body và `fromJson`, trả `Future<Result<Model>>` khi có dữ liệu để parse. Model JSON nằm ở `data/model/model_<tên>.dart`.
3. **Domain và mapping** · Entity ở `domain/entities/`. Chỉ gắn `@entityField` vào field app cần, ví dụ tên/email để hiển thị và ID nếu cần định danh. Field khác giữ ở data layer. Chạy `make entity <đường_dẫn_model>` và kiểm tra entity/mapper chỉ lấy field đã chọn. Hợp đồng ở `domain/repositories/` trả `Future<Result<Entity>>`. Implementation ở `data/repositories/` gọi remote, dùng `toEntity()` hoặc mapper tương ứng và giữ `Failure(code, message, res)`.
4. **Nghiệp vụ** · BLoC gọi repository trực tiếp cho luồng đơn giản. Chính sách cache/local/remote thuộc repository. Use case `@injectable` triển khai `BaseUseCase<Output, Params>` trong `domain/usecases/` khi có quy tắc riêng hoặc cần điều phối nhiều bước. Inject repository qua constructor của use case và inject repository/use case vào BLoC.
5. **Presentation** · Trong `presentation/`, event mang tham số, Freezed state chứa dữ liệu/nghiệp vụ, BLoC xử lý event. Cập nhật bằng `emit(state.copyWith(...))`. Nối list bằng spread hoặc `.toList()` rồi `addAll()`. View dùng `buildSuccessView()`, đọc `state`, gọi `emitEvent(...)` từ tương tác. Dùng `args`/`getArgs<T>()` để đọc route arguments, `onInitArgs()` để chuyển thành event. Kiểm tra route đã có trong `AppRouter`. Điều hướng bằng `pushNamed(AppRouter.<feature>, arguments: ...)`, `back()`, `pushReplacementNamed()` hoặc `pushNamedAndRemoveAll()`.

Mẫu lấy user. Remote `getUser(id): Future<Result<ModelUser>>` gọi `NetworkModule.instance.get<ModelUser>(endpoint: '/users/$id', fromJson: (json) => ModelUser.fromJson(json))`. Repository `getUser(id): Future<Result<UserEntity>>` trả `_remote.getUser(id).toEntity()`. Event mang `final int userId`, state có `UserEntity? user`. Handler gọi helper với `() => _repository.getUser(event.userId)` rồi emit `state.copyWith(user: user)`. View gửi event và đọc `state.user`, kể cả lúc chưa có user.

## Handler và trạng thái màn hình

- Cập nhật state đơn giản viết inline trong constructor. API, nhiều nhánh hoặc nhiều bước dùng method riêng, đăng ký `on<Event>(onHandle)`. Handler đồng bộ trả `void`, handler async trả `Future<void>` và await tác vụ.

```dart
on<UpdateStateEvent>((event, emit) {
  emit(state.copyWith(value: event.value));
});
on<LoadEvent>(onLoad);
```

- Tải khi BLoC khởi tạo dùng `onInitBloc()` → `super.onInitBloc()` → `WidgetsBinding.instance.addPostFrameCallback((_) { if (!isClosed) add(const LoadEvent()); })`. Post-frame cho handler đăng ký xong trước khi nhận event. `add()` chỉ gửi event. UI cần chờ request thì dùng Future của thao tác, ví dụ `refreshPage()`.
- Trong handler API, `await runNetworkCatching<T>(onAction: () => _repository.fetch(...), onSuccess: (data) => emit(state.copyWith(...)))`. Core gọi `onSuccess` rồi phát success. Helper không await callback kết quả. Đặt thao tác async cần đợi vào repository, use case hoặc `onAction`.
- `viewState` điều khiển màn hình qua `BaseViewState`. `LoadingNetworkType.normal` mặc định phát `ViewStateEventLoading()`. `overlay` chặn tương tác bằng overlay. `none` dành cho indicator riêng hoặc tác vụ nền. Import `package:core_bloc/common/network_catching.dart` để dùng enum.
- Mặc định `enableListenError: true` và thiếu `onFailure` thì core phát `ViewStateEventFailure(code, message, res)`. `onFailure` thay nhánh mặc định để xử lý riêng. Nếu callback cần màn hình lỗi, tự phát event lỗi đó. `enableListenError: false` tắt lỗi mặc định và vẫn cho callback chạy. Tác vụ tự quản lý có thể gửi `ViewStateEventLoading()`, `ViewStateEventSuccess()`, `ViewStateEventFailure(...)` qua `viewState.add`.
- `enableListenBuilderLoading`/`enableListenBuilderError` áp dụng cho cả view. Override `buildLoadingView()`/`buildFailureView(ViewStateFailure error)` nếu cần UI riêng. Giữ vòng đời BLoC con khi màn cha đổi trạng thái.
- `enableAutomaticConnectionRecovery` mặc định `false`. Khi bật, `Result.isNotConnect` làm core đợi kết nối, hiện snackbar chờ mạng và thử lại một lần. Bật khi thao tác an toàn để gửi lại.

## Phân trang

- View dùng `WidgetListView.builder(controller: bloc.scrollController, onRefresh: bloc.onRefresh, itemCount: state.listUser.length, itemBuilder: ...)`. Core gọi `onLoadMore()` lúc chạm đáy nếu còn trang, chưa load more/refresh. Footer `WidgetWait` tự xuất hiện với `CoreScrollController` khi list có item và `isMoreEnable == true`. View chỉ đếm/dựng item dữ liệu. `runPaginatedRequest` nhả khóa `isLoadMore` khi xong.
- Mẫu `ListSample` dùng `@Default([]) List<UsersEntity> listUser`, `page = 1`, `limit = 20`. Event khai báo `final bool isLoad` và `const GetUsersListSampleEvent([this.isLoad = true])`. Đăng ký `on<GetUsersListSampleEvent>(onGetListUser)`, tải đầu gửi event mặc định qua post-frame. `onLoadMore()` tăng `page`, `add(const GetUsersListSampleEvent(false))`, gọi `super.onLoadMore()`. `onRefresh()` đặt `page = 1` rồi `return refreshPage(GetUsersListSampleEvent(false))`.
- Handler gọi `await runPaginatedRequest<List<UsersEntity>>(event, onAction: () => _repository.listApi(limit, page), ...)`. Dùng `event.isLoad ? LoadingNetworkType.normal : LoadingNetworkType.none`. Trong `onSuccess`, trang đầu thay list, trang sau nối vào bản sao. Cập nhật `isMoreEnable` rồi emit list. Ưu tiên metadata, hoặc dùng `data.length >= limit` nếu API trả trang cuối ngắn. Core bỏ phản hồi bị refresh thay thế. Widget đợi Future từ `refreshPage` để đóng indicator.
- Dùng đúng page/offset/cursor theo API của feature. Kiểm tra tải đầu, load more liên tiếp ít nhất hai lượt, refresh từ trang sau, phản hồi cũ về muộn và hết dữ liệu.

## Tích hợp core

- **Storage** · Khởi tạo trước khi đọc dữ liệu lưu. `await Storage.setString`/`Storage.getString` và cặp tương ứng cho `int`, `double`, `bool`. Token/chuỗi nhạy cảm dùng `await Storage.setStringSecure`/`await Storage.getStringSecure`. Đọc và ghi cùng key/backend. Xóa bằng `remove`/`clear` hoặc `removeSecure`/`clearSecure` đúng phạm vi.
- **Chia sẻ** · `@PublicState()` trên tham số factory Freezed, `@PublicEvent()` trên class event. Builder quét `lib/feature/**/presentation/*_bloc.dart`. `make build` sinh `lib/shared/feature_access.g.dart` và `feature_access_bindings.g.dart` khi có khai báo hợp lệ. Import file chính, gọi `FeatureAccess.initialized()` trước khi tạo BLoC sở hữu. Đọc `featAccess.<field>`, nghe `featAccess.<field>Stream` hoặc dùng `PublicBuilder(listenable: featAccess.<field>Listenable, builder: ...)`. Gọi event sinh sẵn, ví dụ `featAccess.submitExampleEvent(...)`, với tham số theo constructor khi BLoC sở hữu đang hoạt động.
- **Layout** · Màn quản lý tab là một feature. Mỗi tab có route trong `lib/router/app_router.dart`. Gắn `@RegisterLayout(AppRouter.<route>)` trên class view trong `lib/feature/**/presentation/*_view.dart`. `make layout` → import `router/layout_registry.g.dart` → `LayoutRegistry.initialized()` trước `runApp` → `LayoutRegistry.takeOut(AppRouter.<route>, args: ...)`. Lệnh cũng sinh `FeatureAccess` khi có public annotation. Chỉ import output thực sự được sinh.
- **UI** · Dùng `WidgetAppbar`, `WidgetListView`/`.builder`/`.separated`, `WidgetWait`. Helper toàn cục cần `coreNavigatorKey`. Dialog/sheet dùng `coreDialog`/`coreBottomSheet` với `title`, `body`, `actions: List<ButtonAction>`. Chọn `successSnackBar`, `errorSnackBar`, `warningSnackBar` hoặc `coreSnackBar` theo tình huống. Request dùng `LoadingNetworkType.overlay` để core đóng/mở. Tác vụ tự quản lý dùng `runWithLoadingOverlay` hoặc `unawaited(openLoadingOverlay())` rồi `closeLoadingOverlay()` trong `finally`. Future mở overlay hoàn tất khi đóng.
- **Tổ chức view** · UI ngắn viết trực tiếp. Cụm dài tách getter `Widget get _build...` trong view state, đọc `context`, `bloc`, `state` hiện tại. UI lặp cùng cấu trúc tách widget riêng trong feature và truyền tham số. Quy ước widget toàn app theo dự án.
- **Kiểm tra** · Sửa source rồi generate lại `*.freezed.dart`, `injection.config.dart` và registry. `make state <feature>` khi chỉ đổi Freezed, `make build` khi đổi DI/state/annotation, `make layout` khi đổi đăng ký layout. Chạy analyzer và mở route thật để kiểm tra loading, thành công và lỗi.
