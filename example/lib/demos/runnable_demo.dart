import 'package:flutter/material.dart';

/// A demo that plays media: a real page, not console output.
///
/// The framework's interesting behaviour (recovery, watchdogs, engine
/// selection, lyrics timing) only shows up against a running player, so the
/// example ships these pages next to the printed module tour.
final class RunnableDemo {
  /// Creates a runnable demo entry.
  const new({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.purposeZh,
    required this.purposeEn,
    required this.builder,
  });

  /// Stable identifier shown in the list.
  final String id;

  /// Chinese display name.
  final String nameZh;

  /// English display name.
  final String nameEn;

  /// What the page demonstrates (Chinese).
  final String purposeZh;

  /// What the page demonstrates (English).
  final String purposeEn;

  /// Builds the page.
  final WidgetBuilder builder;
}
