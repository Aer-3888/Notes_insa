import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';

class AssociationNotificationHelpScreen extends StatelessWidget {
  const AssociationNotificationHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(title: const Text('Rappels non reçus ?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          CampusSpacing.gutter,
          CampusSpacing.x4,
          CampusSpacing.gutter,
          CampusSpacing.x8,
        ),
        children: <Widget>[
          Text(
            'Les rappels sont locaux et peuvent arriver un peu après l’heure '
            'prévue sur Android.',
            style: context.text.bodyLarge,
          ),
          const SizedBox(height: CampusSpacing.x4),
          const _HelpCard(
            title: 'À vérifier d’abord',
            body:
                'Autorise les notifications de Campus Hub et vérifie que le '
                'mode Ne pas déranger, Concentration ou économie d’énergie ne '
                'bloque pas les alertes.',
          ),
          if (isAndroid) ...<Widget>[
            const _HelpCard(
              title: 'Samsung',
              body:
                  'Réglages > Batterie et maintenance appareil > Batterie > '
                  'Limites utilisation arrière-plan. Retire Campus Hub des apps '
                  'en veille profonde ou ajoute-le aux apps jamais en veille.',
            ),
            const _HelpCard(
              title: 'Xiaomi, Redmi et POCO',
              body:
                  'Dans les infos de l’app, autorise l’activité en arrière-plan '
                  'ou enlève les restrictions de batterie. Si le téléphone le '
                  'propose, autorise aussi le démarrage automatique.',
            ),
            const _HelpCard(
              title: 'OnePlus, Oppo et Realme',
              body:
                  'Dans les infos de l’app ou Batterie, autorise l’activité en '
                  'arrière-plan et désactive l’optimisation de veille pour Campus Hub.',
            ),
            Padding(
              padding: const EdgeInsets.only(top: CampusSpacing.x2),
              child: Text(
                'Les intitulés changent selon le modèle. Ces réglages peuvent '
                'augmenter légèrement la consommation de batterie.',
                style: context.text.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: CampusSpacing.x3),
    child: Padding(
      padding: const EdgeInsets.all(CampusSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: CampusSpacing.x1),
          Text(body, style: context.text.bodyMedium),
        ],
      ),
    ),
  );
}
