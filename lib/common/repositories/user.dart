import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:whatsup/common/models/user.dart';
import 'package:whatsup/common/providers.dart';
import 'package:whatsup/common/repositories/auth.dart';
import 'package:whatsup/common/repositories/storage.dart';
import 'package:whatsup/common/util/constants.dart';
import 'package:whatsup/common/util/ext.dart';
import 'package:whatsup/common/util/logger.dart';

final userRepositoryProvider = Provider((ref) {
  return UserRepository(
    db: ref.read(dbProvider),
    ref: ref,
    authRepository: ref.read(authRepositoryProvider),
  );
});

final userFetchProvider = FutureProvider((ref) {
  return ref.read(userRepositoryProvider).getUser();
});

final userStream = StreamProvider.family<UserModel, String>((ref, id) {
  return ref.watch(userRepositoryProvider).userStream(id);
});

class UserRepository {
  final FirebaseFirestore _db;
  final AuthRepository _authRepository;
  final Ref _ref;
  static final logger = AppLogger.getLogger((UserRepository).toString());

  const UserRepository({
    required FirebaseFirestore db,
    required AuthRepository authRepository,
    required Ref ref,
  })  : _db = db,
        _authRepository = authRepository,
        _ref = ref;

  /// Get a snapshot of the current user. It will return `None` if the user is not logged in
  /// or the user does not exists in the database.
  Future<Option<UserModel>> getUser() async {
    final maybeUser = _authRepository.currentUser;
    if (maybeUser.isNone()) {
      logger.d("Attempted to get user without being logged in");
      return const Option.none();
    }
    final user = maybeUser.unwrap();
    final json = await users.doc(user.uid).get();
    if (json.data() == null) {
      logger.d("The current logged in user does not exists in the database");
      return const Option.none();
    }
    return Option.of(json.data()!);
  }

  Future<void> create({
    required String name,
    required Option<File> avatar,
    required Function(String err) onError,
    required VoidCallback onSuccess,
  }) async {
    try {
      final user = _authRepository.currentUser;
      if (user.isNone()) {
        logger.d("Attempted to get user without being logged in");
        return;
      }
      final userId = user.unwrap();
      String profileImage = await avatar.match(
        () async => kDefaultAvatarUrl,
        (file) async {
          final url = await _ref.read(storageRepositoryProvider).uploadImage(
                path: "$kUsersCollectionId/${userId.uid}/avatar",
                file: avatar.unwrap(),
              );
          return url;
        },
      );
      final newUser = UserModel(
        uid: userId.uid,
        name: name,
        profileImage: profileImage,
        phoneNumber: userId.phoneNumber,
        isOnline: true,
      );
      _db.collection("users").doc(newUser.uid).set(newUser.toMap());
      onSuccess();
    } on FirebaseAuthException catch (e) {
      onError(_mapError(e.code));
    } catch (e) {
      onError(_mapError(e.toString()));
    }
  }

  String _mapError(String code) {
    logger.e("Error code: $code");
    switch (code) {
      default:
        return "Something went wrong";
    }
  }

  CollectionReference<UserModel> get users {
    return _db.collection(kUsersCollectionId).withConverter<UserModel>(
          fromFirestore: (snapshot, _) => UserModel.fromMap(snapshot.data()!),
          toFirestore: (user, _) => user.toMap(),
        );
  }

  Stream<UserModel> userStream(String uid) {
    return users.doc(uid).snapshots().map((event) => event.data()!);
  }
}