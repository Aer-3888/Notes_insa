// App navigation drawer.
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/login_screen.dart';
import '../screens/raw_json_viewer_screen.dart';
import '../screens/config_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/dashboard_screen.dart';

enum DrawerItem { notes, rawJson, config, settings }

// Navigation drawer widget.
class AppDrawer extends StatelessWidget {
  final DrawerItem selected;
  const AppDrawer({super.key, this.selected = DrawerItem.notes});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.indigo),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 30,
                  child: Icon(Icons.person, size: 35, color: Colors.indigo),
                ),
                SizedBox(height: 10),
                Text(
                  "Étudiant",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.school,
              color: selected == DrawerItem.notes ? Colors.indigo : Colors.grey,
            ),
            title: Text(
              'Mes Notes',
              style: TextStyle(
                fontWeight: selected == DrawerItem.notes
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: selected == DrawerItem.notes
                    ? Colors.indigo
                    : Colors.black87,
              ),
            ),
            selected: selected == DrawerItem.notes,
            selectedTileColor: Colors.indigo.withValues(alpha: .12),
            onTap: () {
              Navigator.pop(context);

              if (selected != DrawerItem.notes) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DashboardScreen(),
                  ),
                );
              }
            },
          ),

          ListTile(
            leading: Icon(
              Icons.code,
              color: selected == DrawerItem.rawJson
                  ? Colors.indigo
                  : Colors.grey,
            ),
            title: Text(
              'Voir JSON Brut',
              style: TextStyle(
                color: selected == DrawerItem.rawJson
                    ? Colors.indigo
                    : Colors.black87,
              ),
            ),
            selected: selected == DrawerItem.rawJson,
            selectedTileColor: Colors.indigo.withValues(alpha: .08),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RawJsonViewerScreen(),
                ),
              );
            },
          ),

          ListTile(
            leading: Icon(
              Icons.settings,
              color: selected == DrawerItem.config
                  ? Colors.indigo
                  : Colors.grey,
            ),
            title: Text(
              'Config',
              style: TextStyle(
                color: selected == DrawerItem.config
                    ? Colors.indigo
                    : Colors.black87,
              ),
            ),
            selected: selected == DrawerItem.config,
            selectedTileColor: Colors.indigo.withValues(alpha: .08),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ConfigScreen()),
              );
            },
          ),

          ListTile(
            leading: Icon(
              Icons.tune,
              color: selected == DrawerItem.settings
                  ? Colors.indigo
                  : Colors.grey,
            ),
            title: Text(
              'Settings',
              style: TextStyle(
                color: selected == DrawerItem.settings
                    ? Colors.indigo
                    : Colors.black87,
              ),
            ),
            selected: selected == DrawerItem.settings,
            selectedTileColor: Colors.indigo.withValues(alpha: .08),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),

          const Divider(),

          // Logout Option
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Déconnexion',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              // Delete credentials
              await AuthService().clear();

              if (context.mounted) {
                Navigator.pop(context);

                // Reset App to Login Screen
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
