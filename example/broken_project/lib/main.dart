import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.errorCode});

  final String errorCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('home.title'.tr()),
        Text(tr('home.subtitle', namedArgs: {'name': 'Ali'})),
        Text('cart.checkout'.tr()),
        Text('errors.$errorCode'.tr()),
        Text('home.titel'.tr()),
      ],
    );
  }
}
