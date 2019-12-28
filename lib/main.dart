import 'package:flutter/material.dart';
import 'drawer.dart';
import 'package:cavokator_flutter/utils/shared_prefs.dart';
import 'package:cavokator_flutter/utils/theme_me.dart';


void main() => runApp(new Cavokator());

/// TODO: LAUNCH CHECKLIST
/// Is the current version OK? Update it?
/// Update changelog?
/// Are we using the correct server?


class Cavokator extends StatefulWidget {
  @override
  _CavokatorState createState() => _CavokatorState();
}

class _CavokatorState extends State<Cavokator> {
  String _thisAppVersion = "3.0 beta";
  Brightness _myBrightness = Brightness.light;
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _restoreThemePreferences();
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Cavokator",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        brightness: _myBrightness,
      ),
      home: Container(
        color: ThemeMe.apply(_isDark, DesiredColor.MainBackground),
        child: SafeArea(
          top: false, right: false, left: false, bottom: true,
          child: DrawerPage(
            changeBrightness: callbackBrightness,
            savedThemeDark: _myBrightness == Brightness.dark ? true : false,
            thisAppVersion: _thisAppVersion,
          ),
        ),
      ),
    );
  }


  void callbackBrightness(Brightness thisBrightness) {
    setState(() {
      _myBrightness = thisBrightness;

      if (thisBrightness == Brightness.dark) {
        _isDark = true;
      } else {
        _isDark = false;
      }

    });
  }


  void _restoreThemePreferences () {
    SharedPreferencesModel().getAppTheme().then((onValue) {
      setState(() {
        _myBrightness = onValue == "DARK" ? Brightness.dark : Brightness.light;
        _isDark = onValue == "DARK" ? true : false;
      });
    });
  }

}
