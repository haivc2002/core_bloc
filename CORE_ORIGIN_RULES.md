# Hướng dẫn phát triển với core_bloc

Đặt file này ở gốc ứng dụng Flutter. Dùng kiến trúc và helper của `core_bloc` khi tạo feature. Ví dụ `example` trong tài liệu minh họa luồng triển khai. Lấy nghiệp vụ, endpoint, JSON, điều kiện xác thực và quy ước phân trang từ yêu cầu của dự án đang làm.

## 1. Chuẩn bị dự án mới

1. Đặt thư mục `core_bloc/` cạnh `pubspec.yaml` của app. Copy `core_bloc/Makefile` ra gốc app. Chạy các lệnh `make` từ thư mục này.
2. Thêm các dependency dưới đây và chạy `flutter pub get`. Kiểm tra `environment.sdk` của `core_bloc/pubspec.yaml` trước khi chọn phiên bản SDK và generator.

   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     flutter_localizations:
       sdk: flutter
     core_bloc:
       path: core_bloc
     freezed_annotation: ^3.1.0
     injectable: ^3.0.0

   dev_dependencies:
     flutter_test:
       sdk: flutter
     build_runner: ^2.16.0
     freezed: any
     injectable_generator: ^3.1.3
   ```

   Giữ cấu hình lint của app. Chỉ thêm `go_router_builder` hoặc `riverpod_generator` khi dự án dùng chúng.
3. Tạo `lib/module/network_module.dart`. Import `package:core_bloc/core_bloc.dart` và đặt `static final NetworkService instance = NetworkService(baseUrl: ...)` trong `NetworkModule`. Dùng base URL theo môi trường của app. Nếu cần xác thực, cấu hình `NetworkAuthConfig` tại đây và dùng `withToken: true` cho các request cần token.
4. Chạy `make module <tên_module>` để tạo feature đầu tiên, ví dụ `make module example`. Lệnh tạo scaffold, tạo `lib/dependence/injection.dart` nếu thiếu, tạo hoặc cập nhật `lib/router/app_router.dart` và chạy build runner để sinh DI và Freezed. Kiểm tra log build và các file đầu ra. Các feature sau dùng chung bootstrap này.
5. Nối DI và router vào `main.dart`. Import `core_bloc.dart`, `flutter_localizations.dart`, `dependence/injection.dart` và `router/app_router.dart` từ package của app.

   ```dart
   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     Dependencies.initialized();
     await Storage.initialized(); // Nếu app dùng Storage.
     runApp(const MyApp());
   }
   ```

   ```dart
   return MaterialApp(
     navigatorKey: coreNavigatorKey,
     initialRoute: AppRouter.example, // Dùng route khởi động của app.
     onGenerateRoute: AppRouter.generateRoute,
     localizationsDelegates: const [
       CoreLocalizations.delegate,
       GlobalMaterialLocalizations.delegate,
       GlobalWidgetsLocalizations.delegate,
       GlobalCupertinoLocalizations.delegate,
     ],
     supportedLocales: const [Locale('vi'), Locale('en')],
     locale: const Locale('vi'),
   );
   ```

   Nếu dùng `LayoutRegistry` hoặc `FeatureAccess`, chạy generator trước rồi import file đã sinh và gọi `LayoutRegistry.initialized()` hoặc `FeatureAccess.initialized()` trước `runApp`. Các builder có thể không sinh file nếu app chưa có annotation tương ứng.

## 2. Triển khai một feature

Bắt đầu bằng `make module <tên_module>`. Giữ lớp, tên file và annotation theo scaffold. Ví dụ cho `make module example`:

```text
lib/feature/example/
├── data/
│   ├── datasource/example_remote.dart           Gọi API và parse response
│   ├── model/                                   Model dữ liệu, thêm khi có hợp đồng JSON
│   └── repositories/example_repository_impl.dart Triển khai repository, chuyển model thành entity
├── domain/
│   ├── entities/                                Kiểu dữ liệu feature dùng, thêm khi cần
│   ├── repositories/example_repository.dart       Hợp đồng của repository
│   └── usecases/                                Luồng nghiệp vụ khi cần
└── presentation/
    ├── example_event.dart                        Hành động và tham số đầu vào
    ├── example_state.dart                        Dữ liệu màn hình và trạng thái nghiệp vụ
    ├── example_state.freezed.dart                Code Freezed tự sinh
    ├── example_bloc.dart                         Xử lý event và cập nhật state
    └── example_view.dart                         Dựng nội dung, gửi event từ tương tác
```

### Bước 1. Xác định luồng nghiệp vụ và dữ liệu

- Trước khi viết, xác định hành động của người dùng, tham số cần truyền, endpoint và method, response, có cần token hay không, dữ liệu nào màn hình cần hiển thị và hành vi khi lỗi. Nếu backend chưa cung cấp hợp đồng, xác nhận phần còn thiếu trước khi cố định endpoint hoặc cấu trúc JSON.
- Mỗi feature sở hữu event, state, repository, model và entity của mình. Khi cần giao tiếp giữa feature, dùng route, `FeatureAccess` hoặc hợp đồng dùng chung phù hợp. Feature layout lấy tab bằng registry theo mục 6.

### Bước 2. Viết datasource và hợp đồng domain

- Datasource remote gọi `NetworkModule.instance` với endpoint, method, query/body và `fromJson`. Trả `Future<Result<Model>>` khi có dữ liệu cần parse. Đặt API và JSON parsing ở data layer.
- Thêm file `model_<tên>.dart` trong `data/model/` khi có JSON thực tế. Chỉ đánh `@entityField` trên những field app đang cần để hiển thị hoặc xử lý nghiệp vụ. Giữ các field còn lại ở data layer và bổ sung vào entity khi có nhu cầu cụ thể. Ví dụ màn danh sách chỉ hiển thị tên và email thì chỉ đánh dấu các field đó, cộng với ID nếu cần để định danh hoặc điều hướng. Chạy `make entity lib/feature/<feature>/data/model/model_<tên>.dart` và kiểm tra entity cùng mapper được sinh đúng tập field đã chọn.
- Thêm method vào hợp đồng repository trong `domain/repositories/`, chẳng hạn `Future<Result<UserEntity>> getUser(int userId)`. Trong repository implementation, gọi datasource và dùng `.toEntity()` hoặc mapper tương ứng. Khi map kết quả, giữ `Failure` cùng `code`, `message`, `res`.
- Đặt chính sách chọn cache/local hoặc remote ở repository. Khi một hành động cần quy tắc riêng hoặc phối hợp nhiều bước nghiệp vụ, thêm `@injectable` use case triển khai `BaseUseCase<Output, Params>` trong `domain/usecases/`. Inject repository qua constructor. Luồng gọi đơn giản có thể đi thẳng từ BLoC vào repository.

Ví dụ ghép luồng lấy user. Với endpoint minh họa `GET /users/{id}`, thêm method vào các class đã sinh sau khi có `ModelUser.fromJson` và mapper sang `UserEntity`.

```dart
// Trong ExampleRemote
Future<Result<ModelUser>> getUser(int userId) {
  return NetworkModule.instance.get<ModelUser>(
    endpoint: '/users/$userId',
    fromJson: (json) => ModelUser.fromJson(json),
  );
}

// Trong ExampleRepository
Future<Result<UserEntity>> getUser(int userId);

// Trong ExampleRepositoryImpl
@override
Future<Result<UserEntity>> getUser(int userId) =>
    _remote.getUser(userId).toEntity();
```

### Bước 3. Nối event, BLoC và state

- Thêm event với tham số cần thiết và thêm các field cần hiển thị vào Freezed state. Inject repository hoặc use case qua constructor của BLoC. Cập nhật state bằng `emit(state.copyWith(...))`. Khi nối danh sách, tạo list mới bằng spread hoặc `.toList()` rồi mới `addAll()`.
- Viết handler inline trong constructor nếu event chỉ cập nhật state đơn giản. Nếu handler gọi API, có nhiều bước hoặc có nhiều nhánh xử lý, tách thành method và truyền tên method vào `on<Event>(handler)`.

```dart
// Trong constructor của BLoC
on<UpdateStateEvent>((event, emit) {
  emit(state.copyWith(value: event.value));
});
on<GetUserExampleEvent>(onGetUser);
```

- Handler đồng bộ dùng `void`. Handler bất đồng bộ dùng `Future<void>` và await tác vụ trước khi kết thúc. Với API, truyền closure vào `onAction` của `runNetworkCatching` và cập nhật state trong `onSuccess`.

Ví dụ lấy user dùng `UserEntity? user` trong factory của `ExampleState` và event `GetUserExampleEvent(this.userId)` với field `final int userId`.

```dart
Future<void> onGetUser(
  GetUserExampleEvent event,
  Emitter<ExampleState> emit,
) async {
  await runNetworkCatching<UserEntity>(
    onAction: () => _repository.getUser(event.userId),
    onSuccess: (user) => emit(state.copyWith(user: user)),
  );
}
```

- Dùng `onInitBloc()` cho event khởi tạo độc lập với View. `BaseBloc` gọi hook này trong constructor, nên đặt `add` trong `WidgetsBinding.instance.addPostFrameCallback` để BLoC con đăng ký xong handler. Gọi `super.onInitBloc()` và kiểm tra `isClosed` trong callback. Nếu event cần callback UI, View gửi event từ `initState()` sau `super.initState()`, hoặc từ `onInitArgs()` khi cần tham số route. Nếu callback có thể mở dialog ngay lúc dựng màn hình, gửi event sau frame đầu và kiểm tra `mounted`.

```dart
@override
void onInitBloc() {
  super.onInitBloc();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (isClosed) return;
    add(GetUserExampleEvent(initialUserId));
  });
}
```

`initialUserId` là tham số khởi tạo của feature. Nếu ID đến từ route, dùng `onInitArgs()` của view để gửi event khi nhận được tham số. `Bloc.add()` chỉ gửi event. Khi UI cần đợi request hoàn tất, trả về Future của cơ chế tương ứng, chẳng hạn `refreshPage()` cho refresh.

### Bước 4. Nối màn hình và kiểm tra feature

- Triển khai nội dung trong `buildSuccessView()`, đọc `state` để hiển thị và gọi `emitEvent(...)` từ tương tác. Dùng `args` hoặc `getArgs<T>()` khi màn hình nhận tham số.
- Với ví dụ trên, nút gửi `emitEvent(GetUserExampleEvent(userId))` và nội dung đọc `state.user`. Nếu chưa có user, hiển thị trạng thái ban đầu phù hợp với feature. Loading và failure chung do `BaseViewState` xử lý.
- Kiểm tra generator đã thêm route vào `AppRouter`. Điều hướng bằng `pushNamed(AppRouter.<feature>, arguments: ...)`, `back()`, `pushReplacementNamed()` hoặc `pushNamedAndRemoveAll()` theo hành vi cần có.
- Chạy `make build` sau khi đổi DI, state hoặc các annotation. Khi chỉ đổi Freezed, có thể dùng `make state <feature>`. Sửa file nguồn rồi generate lại `*.freezed.dart`, `injection.config.dart` và các file registry. Chạy analyzer cho phần đã sửa, mở feature từ route thật và kiểm tra luồng thành công, lỗi và trạng thái loading.

## 3. Trạng thái màn hình và phân trang

`state` của feature chứa dữ liệu và trạng thái nghiệp vụ. `viewState` của `BaseBloc` điều khiển loading, success và failure chung của `BaseViewState`. Ưu tiên để `runNetworkCatching` phát các event chung của cùng request.

| Cấu hình | Hành vi |
| --- | --- |
| `LoadingNetworkType.normal` | Mặc định. Phát `ViewStateEventLoading()` để hiện loading trong màn hình. |
| `LoadingNetworkType.overlay` | Overlay đảm nhiệm loading. Dùng cho thao tác cần chặn tương tác trong lúc chờ. |
| `LoadingNetworkType.none` | Bỏ chỉ báo loading chung. Phù hợp với refresh, load more hoặc UI có indicator riêng. |
| `enableListenError: true` | Mặc định. Core phát `ViewStateEventFailure(code, message, res)` khi có `Failure` và không truyền `onFailure`. |
| `enableListenError: false` | Tắt xử lý lỗi mặc định cho request. Callback `onFailure` vẫn chạy nếu được truyền. |
| `enableAutomaticConnectionRecovery: true` | Mặc định là `false`. Khi nhận `Result.isNotConnect`, core chờ kết nối và thử lại một lần. `BaseViewState` hiện snackbar chờ mạng. Chỉ bật cho thao tác có thể chạy lại an toàn. |

- Core gọi `onSuccess` trước khi phát success. Callback của helper có kiểu `void Function`. Nếu việc lưu dữ liệu hoặc điều phối bất đồng bộ phải xong cùng request, đặt nó trong repository, use case hoặc phần được await của `onAction`.
- `onFailure` thay nhánh lỗi mặc định. BLoC xử lý lỗi nghiệp vụ và gọi callback của event nếu View cần hiện thông báo. Nếu cần màn hình lỗi, gọi `viewState.add(ViewStateEventFailure(code, message, res))` trong `onFailure`. Với tác vụ tự quản lý trạng thái ngoài helper, có thể phát `ViewStateEventLoading()`, `ViewStateEventSuccess()` hoặc `ViewStateEventFailure(...)` trực tiếp.
- Override `buildLoadingView()` hoặc `buildFailureView(ViewStateFailure error)` khi màn hình cần cách hiển thị riêng. `enableListenBuilderLoading` và `enableListenBuilderError` áp dụng cho cả view. Giữ vòng đời của các BLoC con khi màn cha đổi trạng thái.

### Ví dụ phân trang theo ListSample

Nối `WidgetListView.builder` với `bloc.scrollController`. Controller của core theo dõi cuộn tới đáy và gọi `onLoadMore()` khi còn trang và không có lượt load more hoặc refresh đang chờ. `WidgetListView` tự thêm footer `WidgetWait` khi dùng `CoreScrollController`, danh sách có item và `isMoreEnable` là `true`. Footer dùng cờ còn trang. Khóa chống gọi trùng dùng `isLoadMore` và được nhả bởi `runPaginatedRequest`. View chỉ khai báo số item dữ liệu và cách dựng từng item.

Trong scaffold `list_sample`, thêm `@Default([]) List<UsersEntity> listUser` vào state. Khai báo `const GetUsersListSampleEvent([this.isLoad = true])` với `final bool isLoad`. Trong constructor BLoC, đăng ký `on<GetUsersListSampleEvent>(onGetListUser)`. Repository cung cấp `Future<Result<List<UsersEntity>>> listApi(int limit, int page)`. Import `package:core_bloc/common/network_catching.dart` để dùng `LoadingNetworkType`.

```dart
// Các field và method của ListSampleBloc
final int limit = 20;
int page = 1;

@override
void onInitBloc() {
  super.onInitBloc();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (isClosed) return;
    add(const GetUsersListSampleEvent());
  });
}

Future<void> onGetListUser(
  GetUsersListSampleEvent event,
  Emitter<ListSampleState> emit,
) async {
  await runPaginatedRequest<List<UsersEntity>>(
    event,
    onAction: () => _repository.listApi(limit, page),
    loadingType: event.isLoad
        ? LoadingNetworkType.normal
        : LoadingNetworkType.none,
    onSuccess: (data) {
      final users = page == 1 ? <UsersEntity>[] : state.listUser.toList();
      users.addAll(data);
      isMoreEnable = data.length >= limit;
      emit(state.copyWith(listUser: users));
    },
  );
}

@override
void onLoadMore() {
  page++;
  add(const GetUsersListSampleEvent(false));
  super.onLoadMore();
}

@override
Future<void> onRefresh() {
  page = 1;
  return refreshPage(GetUsersListSampleEvent(false));
}
```

Trong `buildSuccessView()`, dùng danh sách này làm `body` của `Scaffold`:

```dart
WidgetListView.builder(
  controller: bloc.scrollController,
  onRefresh: bloc.onRefresh,
  itemCount: state.listUser.length,
  itemBuilder: (_, index) {
    final user = state.listUser[index];
    return ListTile(title: Text(user.lastName ?? 'Không có thông tin'));
  },
)
```

- Giữ cách truyền `page` vào repository theo hợp đồng của feature. Với offset hoặc cursor, đổi giá trị bắt đầu và cách lấy trang tiếp theo theo API. Ưu tiên metadata của API để tính `isMoreEnable`. Phép so sánh `data.length >= limit` trong ví dụ phù hợp khi API trả trang cuối ngắn hơn.
- Khi kéo refresh, `bloc.onRefresh` đặt lại vị trí đầu và trả Future từ `refreshPage(event)`. `WidgetListView` đợi Future đó để kết thúc indicator. Trang đầu thay danh sách và lượt cũ về muộn được core bỏ qua.
- Kiểm tra lần tải đầu, cuộn tải ít nhất hai trang liên tiếp, kéo refresh khi đã ở trang sau và dừng load more khi hết dữ liệu. Với cách nối trên, tự thêm scroll listener hoặc tự chèn footer trong `itemBuilder` sẽ lặp phần core đang làm.

## 4. Lưu dữ liệu trên thiết bị

- Nếu app dùng `Storage`, gọi `await Storage.initialized()` khi bootstrap để sẵn sàng đọc dữ liệu đã lưu. Dùng `await Storage.setString(key, value)` và `Storage.getString(key)` cho chuỗi. Core có các cặp `set`/`get` cho `int`, `double`, `bool` và các hàm `remove`, `clear`.
- Dùng `await Storage.setStringSecure(key, value)` và `await Storage.getStringSecure(key)` cho token, refresh token hoặc chuỗi nhạy cảm. Dùng `removeSecure` hoặc `clearSecure` theo phạm vi cần xóa. Khi đọc và ghi cùng dữ liệu, dùng cùng backend lưu trữ và cùng key.

## 5. Chia sẻ state và event giữa feature

- Đặt `@PublicState()` trên tham số trong factory Freezed state khi feature khác cần đọc hoặc lắng nghe field đó. Đặt `@PublicEvent()` trên class event cần gọi từ bên ngoài. Giữ BLoC trong `lib/feature/**/presentation/*_bloc.dart` để builder phát hiện.
- Chạy `make build`. Khi có dữ liệu hoặc event hợp lệ, core sinh `lib/shared/feature_access.g.dart` và `lib/shared/feature_access_bindings.g.dart`. Import `feature_access.g.dart` và gọi `FeatureAccess.initialized()` trước khi tạo BLoC sở hữu.
- Dùng `featAccess.user` để đọc giá trị, `featAccess.userListenable` với `PublicBuilder` để rebuild khi giá trị đổi, hoặc `featAccess.userStream` để lắng nghe stream. Ví dụ `PublicBuilder(listenable: featAccess.userListenable, builder: (_, user) => Text(user?.lastName ?? 'Chưa có người dùng'))`.
- Với `@PublicEvent()` trên `SubmitExampleEvent`, builder sinh `featAccess.submitExampleEvent(...)`. Truyền tham số theo constructor của event. BLoC sở hữu phải đang hoạt động khi gọi.

## 6. Đăng ký màn hình để nhúng vào layout

- Tổ chức màn quản lý tab như một feature. Giữ route của mỗi tab trong `AppRouter`. Gắn `@RegisterLayout(AppRouter.<route>)` trên class view trong `lib/feature/**/presentation/*_view.dart`.
- Chạy `make layout`, import `router/layout_registry.g.dart`, rồi gọi `LayoutRegistry.initialized()` trong `main()` trước `runApp`. Trong layout, lấy view bằng `LayoutRegistry.takeOut(AppRouter.<route>, args: ...)`. Builder đọc route từ `lib/router/app_router.dart`. `make layout` cũng sinh `FeatureAccess` khi app có public annotation.

## 7. Dùng widget và helper của core trong view

- Dùng `WidgetAppbar` cho app bar của `Scaffold`, `WidgetListView` hoặc `.builder`/`.separated` cho danh sách và `WidgetWait` cho indicator. Dùng các widget core ở những vị trí chúng đã đáp ứng được hành vi cần thiết.
- View sở hữu dialog, bottom sheet và snackbar. Viết nội dung, nút và lời gọi `coreDialog`, `coreBottomSheet`, `successSnackBar`, `warningSnackBar`, `errorSnackBar` hoặc `coreSnackBar` tại View. Dùng `ButtonAction` cho nút trong dialog/sheet. Các helper toàn cục cần `coreNavigatorKey` đã gắn vào app.
- Nếu UI phản ứng với kết quả nghiệp vụ, View truyền callback có kiểu rõ ràng trong event. BLoC gọi callback từ nhánh `onSuccess` hoặc `onFailure` tương ứng, chỉ truyền dữ liệu cần hiển thị. Giữ `BuildContext`, widget và lời gọi helper UI trong View. Kiểm tra `mounted` trong callback trước khi hiển thị vì request có thể hoàn tất sau khi người dùng rời màn hình. Event mang callback UI dùng nội bộ feature, không gắn `@PublicEvent()`.
- Với API dùng `LoadingNetworkType.overlay` để core quản lý vòng đời overlay. Với thao tác tự quản lý, gọi `openLoadingOverlay()` trước khi chạy và `closeLoadingOverlay()` trong `finally`, hoặc dùng `runWithLoadingOverlay(() async { ... })`. Future từ `openLoadingOverlay()` hoàn tất khi overlay đóng. Dùng `unawaited(openLoadingOverlay())` nếu cần chạy việc ngay sau khi mở.
- Viết phần UI nhỏ trực tiếp trong `buildSuccessView()`. Khi một cụm dài, tách thành getter riêng như `Widget get _buildSummary { ... }` ngay trong view state. Getter đọc `context`, `bloc`, `state` có sẵn. Lấy state hiện tại mỗi lần build.
- Nếu nhiều cụm UI có cùng cấu trúc và chỉ khác dữ liệu hoặc callback, tách thành widget riêng trong một file cùng feature rồi truyền tham số. Chờ quy ước riêng của dự án cho widget dùng chung toàn app.

### Ví dụ chuyển lỗi đăng nhập từ BLoC về View

```dart
// Event
final class LoginSampleExampleEvent extends ExampleEvent {
  const LoginSampleExampleEvent({this.dialog});

  final void Function(String message)? dialog;
}

// View
void _submitLogin() {
  emitEvent(LoginSampleExampleEvent(dialog: (message) {
    if (!mounted) return;
    coreDialog(title: 'Đăng nhập thất bại', body: Text(message));
  }));
}

// Trong handler của BLoC. Giữ xử lý thành công của feature trong onSuccess.
await runNetworkCatching<LoginEntity>(
  onAction: () => _repository.loginSampleApi(),
  enableListenError: false,
  onFailure: (_, message, _) => event.dialog?.call(message),
);
```
