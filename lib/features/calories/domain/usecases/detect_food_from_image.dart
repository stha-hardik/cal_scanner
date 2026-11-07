import 'dart:io';

import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../entities/food.dart';
import '../repositories/food_repository.dart';

class DetectFoodFromImage {
  final FoodRepository _repo;
  DetectFoodFromImage(this._repo);

  Future<Either<Failure, Food>> call(File image, {String? note, List<File> moreImages = const []}) {
    return _repo.detectFoodFromImage(image, note: note, moreImages: moreImages);
  }

  /// Asks the AI to correct an earlier estimate using the user's note
  /// (and the photo, if it still exists).
  Future<Either<Failure, Food>> reestimate(Food current, String note, {File? image}) {
    return _repo.reestimateFood(current, note, image: image);
  }
}

