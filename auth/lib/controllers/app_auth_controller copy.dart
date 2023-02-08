import 'dart:io';

import 'package:auth/models/app_response_model.dart';
import 'package:auth/models/user.dart';
import 'package:conduit/conduit.dart';
import 'package:jaguar_jwt/jaguar_jwt.dart';

class AppAuthController extends ResourceController {
  final ManagedContext managedContext;

  AppAuthController(this.managedContext);

  @Operation.post()
  Future<Response> signIn(@Bind.body() User user) async {
    if (user.password == null || user.username == null) {
      return Response.badRequest(
          body:
              AppResponseModel(message: "Поля password username обязательны"));
    }

    try {
      final qFindUser = Query<User>(managedContext)
        ..where((table) => table.username).equalTo(user.username)
        ..returningProperties(
            (table) => [table.id, table.salt, table.hashPassword]);
      final findUser = await qFindUser.fetchOne();

      if (findUser == null) {
        throw QueryException.input("Пользователь не найден", []);
      }

      final requestHashPassword =
          generatePasswordHash(user.password ?? "", findUser.salt ?? "");

      if (requestHashPassword == findUser.hashPassword) {
        await _updateTokens(findUser.id ?? -1, managedContext);
        final newUser =
            await managedContext.fetchObjectWithID<User>(findUser.id);
        return Response.ok(AppResponseModel(
            data: newUser?.backing.contents, message: "Успещная авторизация"));
      } else {
        throw QueryException.input("Пароль не верный", []);
      }
    } on QueryException catch (error) {
      return Response.serverError(
        body: AppResponseModel(
          message: error.message,
        ),
      );
    }
  }

  @Operation.put()
  Future<Response> signUp(@Bind.body() User user) async {
    if (user.password == null || user.username == null || user.email == null) {
      return Response.badRequest(
          body: AppResponseModel(
              message: "Поля password username email обязательны"));
    }
    final salt = generateRandomSalt();
    final hashPassword = generatePasswordHash(user.password ?? "", salt);
    try {
      late final int id;
      await managedContext.transaction((transaction) async {
        final qCreateUser = Query<User>(transaction)
          ..values.username = user.username
          ..values.email = user.email
          ..values.salt = salt
          ..values.hashPassword = hashPassword;
        final createdUser = await qCreateUser.insert();
        id = createdUser.asMap()["id"];
        await _updateTokens(id, transaction);
      });
      final userData = await managedContext.fetchObjectWithID<User>(id);
      return Response.ok(AppResponseModel(
        data: userData?.backing.contents,
        message: "Успешная регистрация",
      ));
    } on QueryException catch (error) {
      return Response.serverError(
        body: AppResponseModel(
          message: error.message,
        ),
      );
    }
  }

  Future<void> _updateTokens(int id, ManagedContext transaction) async {
    final Map<String, dynamic> tokens = _getTokens(id);
    final qUpdateTokens = Query<User>(transaction)
      ..where((user) => user.id).equalTo(id)
      ..values.accessToken = tokens["access"]
      ..values.refreshToken = tokens["refresh"];
    await qUpdateTokens.updateOne();
  }

  @Operation.post("refresh")
  Future<Response> refreshToken(
      @Bind.path("refresh") String refreshToken) async {
    final User fetchedUser = User();

    // connect to DB
    // find user (by token OR id)
    // check token
    // if success fetch user

    return Response.ok(
      AppResponseModel(data: {
        "id": fetchedUser.id,
        "refreshToken": fetchedUser.refreshToken,
        "accessToken": fetchedUser.accessToken,
      }, message: "Успешное обновление токенов")
          .toJson(),
    );
  }

  Map<String, dynamic> _getTokens(int id) {
    // TODO: remove when release
    final key = Platform.environment["SECRET_KEY"] ?? "SECRET_KEY";
    final accessClaimSet =
        JwtClaim(maxAge: Duration(hours: 1), otherClaims: {"id": id});
    final refreshClaimSet = JwtClaim(otherClaims: {"id": id});
    final tokens = <String, dynamic>{};
    tokens["access"] = issueJwtHS256(accessClaimSet, key);
    tokens["refresh"] = issueJwtHS256(refreshClaimSet, key);
    return tokens;
  }
}
