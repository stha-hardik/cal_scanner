import '../../domain/entities/food.dart';

class FoodModel {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double quantity;
  final String? imageUrl;
  final DateTime timestamp;
  final String? note;
  final String? photoPath;
  final String? details;

  const FoodModel({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.quantity,
    this.imageUrl,
    required this.timestamp,
    this.note,
    this.photoPath,
    this.details,
  });

  factory FoodModel.fromJson(Map<String, dynamic> json) {
    return FoodModel(
      id: json['id'] as String,
      name: json['name'] as String,
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      carbs: (json['carbs'] as num).toDouble(),
      fat: (json['fat'] as num).toDouble(),
      quantity: (json['quantity'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      note: json['note'] as String?,
      photoPath: json['photoPath'] as String?,
      details: json['details'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'quantity': quantity,
      'imageUrl': imageUrl,
      'timestamp': timestamp.toIso8601String(),
      'note': note,
      'photoPath': photoPath,
      'details': details,
    };
  }

  Food toDomain() {
    return Food(
      id: id,
      name: name,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      quantity: quantity,
      imageUrl: imageUrl,
      timestamp: timestamp,
      note: note,
      photoPath: photoPath,
      details: details,
    );
  }

  factory FoodModel.fromDomain(Food food) {
    return FoodModel(
      id: food.id,
      name: food.name,
      calories: food.calories,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
      quantity: food.quantity,
      imageUrl: food.imageUrl,
      timestamp: food.timestamp,
      note: food.note,
      photoPath: food.photoPath,
      details: food.details,
    );
  }
}

