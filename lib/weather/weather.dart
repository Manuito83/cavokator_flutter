import 'package:cavokator_flutter/weather/wx_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:cavokator_flutter/json_models/wx_json.dart';
import 'package:cavokator_flutter/private.dart';
import 'package:cavokator_flutter/utils/custom_sliver.dart';
import 'package:cavokator_flutter/weather/wx_item_builder.dart';
import 'package:cavokator_flutter/utils/pretty_duration.dart';
import 'package:cavokator_flutter/utils/shared_prefs.dart';
import 'package:cavokator_flutter/weather/wx_colorize.dart';
import 'package:cavokator_flutter/weather/wx_split_tafor.dart';
import 'package:cavokator_flutter/utils/theme_me.dart';
import 'package:connectivity/connectivity.dart';
import 'package:share/share.dart';
import 'dart:io';
//import 'package:flutter_speed_dial/flutter_speed_dial.dart';


class WeatherPage extends StatefulWidget {

  final bool isThemeDark;
  final Widget myFloat;
  final Function callback;
  final bool showHeaders;
  final Function hideBottomSheet;
  final Function showBottomSheet;
  final double recalledScrollPosition;
  final Function notifyScrollPosition;

  WeatherPage({@required this.isThemeDark, @required this.myFloat,
               @required this.callback, @required this.showHeaders,
               @required this.hideBottomSheet, @required this.showBottomSheet,
               @required this.recalledScrollPosition,
               @required this.notifyScrollPosition});

  @override
  _WeatherPageState createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _formKey = GlobalKey<FormState>();
  final _myTextController = new TextEditingController();

  final _myMainScrollController = ScrollController();

  Timer _ticker;

  bool _splitTafor = true;

  String _userSubmitText;
  List<String> _myRequestedAirports = new List<String>();
  List<WxJson> _myWeatherList = new List<WxJson>();
  bool _apiCall = false;

  String mySharedWeather = "";

  int _hoursBefore = 10;
  bool _mostRecent = true;

  @override
  void initState() {
    super.initState();

    _restoreSharedPreferences();
    SharedPreferencesModel().setSettingsLastUsedSection("0");

    // Delayed callback for FAB
    Future.delayed(Duration.zero, () => fabCallback());

    _ticker = new Timer.periodic(Duration(seconds:30), (Timer t) => _updateTimes());

    _userSubmitText = _myTextController.text;
    _myTextController.addListener(onInputTextChange);

    _myMainScrollController.addListener(onMainScrolled);

    // TODO (maybe?): setting to deactivate this?
    Future.delayed(Duration(milliseconds: 500), () {
      _myMainScrollController.animateTo(
        widget.recalledScrollPosition,
        duration: Duration(milliseconds: 1500),
        curve: Curves.easeInOut,
      );
    });

  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).requestFocus(new FocusNode()),
          child: CustomScrollView(
            controller: _myMainScrollController,
            slivers: _buildSlivers(context),
          ),
        );
      },
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    List<Widget> slivers = new List<Widget>();

    slivers.add(_myAppBar());
    slivers.add(_inputForm());

    var wxSect = _weatherSections();
    for (var section in wxSect) {
      slivers.add(section);
    }

    return slivers;
  }

  Widget _myAppBar() {
    return SliverAppBar(
      iconTheme: IconThemeData(
        color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
      ),
      title: Text(
          "Weather",
        style: TextStyle(
          color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
        ),
      ),
      expandedHeight: widget.showHeaders ? 150 : 0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/weather_header.jpg'),
              fit: BoxFit.fitWidth,
              colorFilter: widget.isThemeDark == true
                  ? ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken)
                  : null,
            ),
          ),
        ),
      ),
      actions: <Widget>[
        IconButton(
          icon: Icon(Icons.settings),
          color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
          onPressed: () {
            return _showSettings();
          },
        ),
        IconButton(
          icon: Icon(Icons.share),
          color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
          onPressed: () {
            Share.share(mySharedWeather);
          },
        ),
      ],
    );
  }

  Widget _inputForm() {
    return CustomSliverSection(
      child: Container(
        margin: EdgeInsets.fromLTRB(10, 10, 10, 50),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
          border: Border.all(color: Colors.grey),
          color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainBackground)
          //color: Colors.grey[200],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(10, 0, 0, 0),
                      ),
                      ImageIcon(
                        AssetImage("assets/icons/drawer_wx.png"),
                        color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(0, 0, 20, 0),
                      ),
                      Expanded(
                        child: TextFormField(
                          style: TextStyle(
                            fontSize: 14,
                          ),
                          keyboardType: TextInputType.text,
                          maxLines: null,
                          controller: _myTextController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: "Enter ICAO/IATA airports",
                          ),
                          validator: (value) {
                            if (value.isEmpty) {
                              return "Please enter at least one valid airport!";
                            } else {
                              // Try to parse some airports
                              // Split the input to suit or needs
                              RegExp exp = new RegExp(r"([a-z]|[A-Z]){3,4}");
                              Iterable<Match> matches =
                                  exp.allMatches(_userSubmitText);
                              matches.forEach(
                                  (m) => _myRequestedAirports.add(m.group(0)));
                            }
                            if (_myRequestedAirports.isEmpty) {
                              return "Could not identify a valid airport!";
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.all(10),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(10, 0, 0, 0),
                      ),
                      ButtonTheme(
                        minWidth: 1.0,
                        buttonColor: ThemeMe.apply(widget.isThemeDark, DesiredColor.Buttons),
                        child: RaisedButton(
                          child: ImageIcon(
                            AssetImage("assets/icons/drawer_wx.png"),
                            color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText)
                          ),
                          onPressed: ()  {
                            _fetchButtonPressed(context, false);
                          },
                        ),
                      ),
                      Padding(padding: EdgeInsets.fromLTRB(0, 0, 10, 0)),
                      ButtonTheme(
                        minWidth: 1.0,
                        buttonColor: ThemeMe.apply(widget.isThemeDark, DesiredColor.Buttons),
                        child: RaisedButton(
                          child: Row(
                            children: <Widget>[
                              ImageIcon(
                                AssetImage("assets/icons/drawer_wx.png"),
                                color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
                              ),
                              Text(" + "),
                              ImageIcon(
                                AssetImage("assets/icons/drawer_notam.png"),
                                color: ThemeMe.apply(widget.isThemeDark, DesiredColor.MainText),
                              ),
                            ],
                          ),
                          onPressed: ()  {
                            _fetchButtonPressed(context, true);
                          },
                        ),
                      ),
                      Padding(padding: EdgeInsets.fromLTRB(0, 0, 10, 0)),
                      ButtonTheme(
                        minWidth: 1.0,
                        buttonColor: ThemeMe.apply(widget.isThemeDark, DesiredColor.Buttons),
                        child: RaisedButton(
                          child: Icon(Icons.delete),
                          onPressed: ()  {
                            setState(() {
                              _apiCall = false;
                              _myWeatherList.clear();
                              SharedPreferencesModel().setWeatherUserInput("");
                              SharedPreferencesModel().setWeatherInformation("");
                              _myTextController.text = "";
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _weatherSections() {
    List<Widget> mySections = List<Widget>();

    if (_apiCall) {
      mySections.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: EdgeInsetsDirectional.only(top: 50),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                ),
            childCount: 1,
          ),
        ),
      );
    } else {
      if (_myWeatherList.isNotEmpty) {
        var wxBuilder = WxItemBuilder(jsonWeatherList: _myWeatherList);
        var wxModel = wxBuilder.result;

        mySharedWeather = "";
        mySharedWeather += "###";
        mySharedWeather += "\n### CAVOKATOR WEATHER ###";
        mySharedWeather += "\n###";

        for (var i = 0; i < wxModel.wxModelList.length; i++) {
          var airportName =
            wxModel.wxModelList[i].airportHeading == null ?
            _myRequestedAirports[i].toUpperCase() :
            wxModel.wxModelList[i].airportHeading;

            mySharedWeather += "\n\n\n### $airportName ###";
            if (!wxModel.wxModelList[i].airportFound){
              mySharedWeather += "\n\nERROR: AIRPORT NOT FOUND!";
            }
            if (wxModel.wxModelList[i].airportWeather.length == 0){
              mySharedWeather += "\n\nNo weather information found in this airport!";
            }
            for (var b = 0; b < wxModel.wxModelList[i].airportWeather.length; b++) {
              var thisItem = wxModel.wxModelList[i].airportWeather[b];

              if (thisItem is AirportMetar){
                for (var met in thisItem.metars) {
                  mySharedWeather += "\n\n## METAR \n$met";
                }
              } else if (thisItem is AirportTafor) {
                for (var taf in thisItem.tafors) {
                  mySharedWeather += "\n\n## TAFOR \n$taf";
                }
              }
            }
            if (i == wxModel.wxModelList.length - 1) {
              mySharedWeather += "\n\n\n\n ### END CAVOKATOR REPORT ###";
            }

          mySections.add(
            SliverStickyHeaderBuilder(
              builder: (context, state) {
                return Padding(
                  padding: EdgeInsets.only(top: 0),
                  child: Container(
                    margin: EdgeInsetsDirectional.only(bottom: 25),
                    height: 60.0,
                    color: (state.isPinned
                        ? ThemeMe.apply(widget.isThemeDark, DesiredColor.HeaderPinned)
                        : ThemeMe.apply(widget.isThemeDark, DesiredColor.HeaderUnpinned)
                        .withOpacity(1.0 - state.scrollPercentage)),
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.local_airport, color: Colors.white),
                        Padding(
                          padding: EdgeInsetsDirectional.only(end: 15),
                        ),
                        Flexible(
                          child: Text(
                            "(${_myRequestedAirports[i].toUpperCase()}) " +
                            airportName,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {

                    if (!wxModel.wxModelList[i].airportFound) {

                      return ListTile(
                        title: Card(
                          elevation: 2,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(15, 20, 15, 20),
                            child: RichText(
                              text: TextSpan(
                                text: "Airport not found!",
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                        ),
                      );

                    } else {

                      final item = wxModel.wxModelList[i].airportWeather[index];

                      if (item is AirportMetar) {

                        // DEBUG METAR HERE (not times)
                        //item.metars[0] = "LEZL 162030Z CAVOK "
                        //"R25R/123456 2000 0800 R23/M2000U";

                        var metarLines = List<Widget>();
                        for (var m = 0; m < item.metars.length; m++) {
                          var wxSpan = MetarColorize(
                              metar: item.metars[m],
                              isThemeDark: widget.isThemeDark,
                              context: context)
                              .getResult;

                          var myText = RichText(text: wxSpan);

                          metarLines.add(myText);

                          if (m < item.metars.length - 1) {
                            metarLines.add(
                              Padding(
                                padding: EdgeInsets.only(bottom: 20),
                              )
                            );
                          }
                        }

                        return ListTile(
                          title: Card(
                            elevation: 2,
                            margin: EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(15, 20, 15, 20),
                              child: Column (
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: metarLines,
                              ),
                            ),
                          ),
                        );

                      }

                      if (item is AirportTafor) {
                        TextSpan wxSpan;
                        var myWeatherLineWidget;

                        var myTaforString = item.tafors[0];
                        List<Widget> myWeatherRows = List<Widget>();
                        if (_splitTafor){
                          List<String> splitList = SplitTafor(taforString: myTaforString).getResult;
                          for (var split in splitList){
                            List<TextSpan> thisSpan = List<TextSpan>();
                            if (split.contains("[/trend]")){
                              var splitAgain = split.split("[/trend]");
                              var firstSpan = TextSpan(
                                text: splitAgain[0],
                                style: TextStyle(
                                  color: ThemeMe.apply(widget.isThemeDark,
                                      DesiredColor.BlueTempo),
                                ),
                              );
                              var secondSpan = MetarColorize(
                                  metar: splitAgain[1],
                                  isThemeDark: widget.isThemeDark,
                                  context: context)
                                  .getResult;
                              thisSpan.add(firstSpan);
                              thisSpan.add(secondSpan);
                              myWeatherRows.add(
                                Container(
                                  padding: EdgeInsets.only(left: 8, top: 8),
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_arrow,
                                        color: ThemeMe.apply(widget.isThemeDark,
                                            DesiredColor.BlueTempo),
                                        size: 16,),
                                      Padding(padding: EdgeInsets.only(left: 2)),
                                      Flexible(
                                        child: RichText(
                                          text: TextSpan(
                                              children: thisSpan
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              List<TextSpan> thisSpan = List<TextSpan>();
                              thisSpan.add(MetarColorize(
                                  metar: split,
                                  isThemeDark: widget.isThemeDark,
                                  context: context)
                                  .getResult);
                              myWeatherRows.add(
                                Row(
                                  children: [
                                    Flexible(
                                      child: RichText(
                                        text: TextSpan(
                                          children: thisSpan,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            myWeatherLineWidget = Column(
                              children: myWeatherRows,
                            );

                          }
                        } else {
                          wxSpan = MetarColorize(
                              metar: myTaforString,
                              isThemeDark: widget.isThemeDark,
                              context: context)
                              .getResult;
                          myWeatherLineWidget = RichText(text: wxSpan);
                        }

                        return ListTile(
                          title: Card(
                            elevation: 2,
                            margin: EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(15, 20, 15, 20),
                              child: myWeatherLineWidget,
                            ),
                          ),
                        );
                      }


                      if (item is MetarTimes){
                        PrettyTimeCombination metarTimeFinal;
                        Color clockIconColor;

                        // DEBUG TIMES HERE
                        // item.metarTimes[0] = DateTime.utc(2019, 8, 19, 19, 10);

                        if (!item.error) {
                          try {
                            var myPrettyDuration = PrettyDuration(
                                referenceTime: item.metarTimes[0],
                                header: "METAR",
                                prettyType: PrettyType.metar
                            );
                            metarTimeFinal = myPrettyDuration.getDuration;
                            clockIconColor = metarTimeFinal.prettyColor;

                          } catch (Exception) {
                            clockIconColor = Colors.red;
                          }
                        } else {
                          clockIconColor = Colors.red;
                        }
                        return ListTile(
                          title: Container(
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.access_time,
                                  color: clockIconColor,
                                ),
                                Padding(padding: EdgeInsets.only(right: 15)),
                                Flexible(
                                  child: Text(
                                    item.error
                                        ? "(no time information)"
                                        : metarTimeFinal.prettyDuration,
                                    style: item.error
                                        ? TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.red,
                                          )
                                        : TextStyle(
                                            fontSize: 14,
                                            color: metarTimeFinal.prettyColor,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (item is TaforTimes){
                        PrettyTimeCombination taforTimeFinal;
                        Color clockIconColor;

                        if (!item.error) {
                          try {
                            var myPrettyDuration = PrettyDuration(
                                referenceTime: item.taforTimes[0],
                                header: "TAFOR",
                                prettyType: PrettyType.tafor
                            );
                            taforTimeFinal = myPrettyDuration.getDuration;
                            clockIconColor = taforTimeFinal.prettyColor;

                          } catch (Exception) {
                            clockIconColor = Colors.red;
                          }
                        } else {
                          clockIconColor = Colors.red;
                        }
                        return ListTile(
                          title: Container(
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.access_time,
                                  color: clockIconColor,
                                ),
                                Padding(padding: EdgeInsets.only(right: 15)),
                                Flexible(
                                  child: Text(
                                    item.error
                                        ? "(no time information)"
                                        : taforTimeFinal.prettyDuration,
                                    style: item.error
                                        ? TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.red,
                                          )
                                        : TextStyle(
                                            fontSize: 14,
                                            color: taforTimeFinal.prettyColor,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );

                        /*
                      return ListTile(
                        title: Text(item.taforTimes[0].toString()),
                      );

                       */
                      }

                    }
                    // Should not arrive here, if all AirportWeather
                    // items are properly coded
                    return null;
                  },
                  childCount: wxModel.wxModelList[i].airportFound
                      ? wxModel.wxModelList[i].airportWeather.length
                      : 1,
                ),
              ),
            ),
          );
          // We need to add another sliver to give extra space
          // SliverPadding results in weird header behaviour, so we
          // use a Container with margin here
          mySections.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) => Container(
                  margin: EdgeInsets.only(bottom: 80),
                ),
                childCount: 1,
              ),
            ),
            //SliverPadding(padding: EdgeInsetsDirectional.only(top: 80)),
          );
        }
      } else {
        mySections.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Container(),
              childCount: 1,
            ),
          ),
        );
      }
    }

    return mySections;
  }

  void _updateTimes(){
    //print("UPDATING WX TICKER: ${DateTime.now().toUtc()}");
    if (_myWeatherList.isNotEmpty){
          setState(() {
            // This will trigger a refresh of weather times
          });
    }
  }




  Future<void> fabCallback() async {
    widget.callback(SizedBox.shrink());
  }


  void _restoreSharedPreferences() async {
    SharedPreferencesModel().getWeatherUserInput().then((onValue) {
      setState(() {
        _myTextController.text = onValue;
      });
    });

    SharedPreferencesModel().getWeatherInformation().then((onValue) {
      if (onValue.isNotEmpty){
        setState(() {
          _myWeatherList = wxJsonFromJson(onValue);
        });
      }
    });

    SharedPreferencesModel().getWeatherRequestedAirports().then((onValue) {
      _myRequestedAirports = onValue;
    });

    SharedPreferencesModel().getWeatherHoursBefore().then((onValue) {
      _hoursBefore = onValue;
    });

  }

  @override
  void dispose() {
    _ticker?.cancel();
    _myTextController.dispose();
    _myMainScrollController.dispose();
    super.dispose();
  }

  void _fetchButtonPressed(BuildContext context, bool fetchBoth) {
    _myRequestedAirports.clear();

    if (_formKey.currentState.validate()) {
      setState(() {
        _apiCall = true;
      });
      _callWeatherApi(fetchBoth).then((weatherJson) {
        setState(() {
          _apiCall = false;
          if (weatherJson != null) {
            _myWeatherList = weatherJson;
          }
        });
      });
    }
    FocusScope.of(context).requestFocus(new FocusNode());
  }

  void onInputTextChange() {
    // Ensure that submitted airports are split correctly
    String textEntered = _myTextController.text;
    // Don't do anything if we are deleting text!
    if (textEntered.length > _userSubmitText.length) {
      if (textEntered.length > 3) {
        // Take a look at the last 4 chars entered
        String lastFourChars =
            textEntered.substring(textEntered.length - 4, textEntered.length);
        // If there is at least a space, do nothing
        bool spaceNeeded = true;
        for (String char in lastFourChars.split("")) {
          if (char == " ") {
            spaceNeeded = false;
          }
        }
        if (spaceNeeded) {
          _myTextController.value = TextEditingValue(
              text: textEntered + " ",
              selection: TextSelection.fromPosition(
                  TextPosition(
                      offset: (textEntered + " ").length)
              ),
          );
        }
      }
    }
    _userSubmitText = textEntered;
  }


  Future<List<WxJson>> _callWeatherApi(bool fetchBoth) async {
    String allAirports = "";
    if (_myRequestedAirports.isNotEmpty) {
      for (var i = 0; i < _myRequestedAirports.length; i++) {
        if (i != _myRequestedAirports.length - 1) {
          allAirports += _myRequestedAirports[i] + ",";
        } else {
          allAirports += _myRequestedAirports[i];
        }
      }
    }

    List<WxJson> wxExportedJson;

    bool wxFailed = false;
    bool notamFailed = false;

    DateTime startRequest = DateTime.now();
    int firstSnackTimeNeeded = 5;

    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) {
        widget.hideBottomSheet();
        Scaffold.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Oops! No Internet connection!',
                style: TextStyle(
                  color: Colors.black,
                )
            ),
            backgroundColor: Colors.red[100],
            duration: Duration(seconds: firstSnackTimeNeeded),
          ),
        );

        Timer(Duration(seconds: 6), () => widget.showBottomSheet());
        return null;

      } else {

        String wxServer = PrivateVariables.apiURL;
        String wxApi = "Wx/GetWx?";
        String wxSource = "source=AppUnknown";
        if (Platform.isAndroid) {
          wxSource = "source=AppAndroid";
        } else if (Platform.isIOS) {
          wxSource = "source=AppIOS";
        } else {
          wxSource = "source=AppOther";
        }
        String wxAirports = "&Airports=$allAirports";

        int internalHoursBefore;
        if (_hoursBefore == 0) {
          _mostRecent = true;
          internalHoursBefore = 10;
        } else {
          _mostRecent = false;
          internalHoursBefore = _hoursBefore;
        }

        String mostRecent = "&mostRecent=$_mostRecent";
        String hoursBefore = "&hoursBefore=$internalHoursBefore";

        String wxUrl = wxServer + wxApi + wxSource + wxAirports + mostRecent + hoursBefore;

        String fetchText;
        if (!fetchBoth) {
          fetchText = "Fetching WEATHER, hold position!";
        } else {
          fetchText = "Fetching WEATHER and NOTAM, hold position!";

          if (_myRequestedAirports.length > 6) {
            fetchText += "\n\nToo many NOTAM requested, this might take time! If it fails, "
                "please try with less next time!";
            firstSnackTimeNeeded = 8;
          }
        }
        widget.hideBottomSheet();
        Scaffold.of(context).showSnackBar(
          SnackBar(
            content: Text(fetchText),
            duration: Duration(seconds: firstSnackTimeNeeded),
          ),
        );

        final response = await http.post(wxUrl).timeout(Duration(seconds: 60));

        if (response.statusCode != 200) {
          wxFailed = true;

        } else {
          wxExportedJson = wxJsonFromJson(response.body);
          SharedPreferencesModel().setWeatherInformation(response.body);
          SharedPreferencesModel().setWeatherUserInput(_userSubmitText);
          SharedPreferencesModel().setWeatherRequestedAirports(_myRequestedAirports);
        }

        if (fetchBoth) {
          String notamServer = PrivateVariables.apiURL;
          String notamApi = "Notam/GetNotam?";
          String notamSource = "source=AppUnknown";
          if (Platform.isAndroid) {
            notamSource = "source=AppAndroid";
          } else if (Platform.isIOS) {
            notamSource = "source=AppIOS";
          } else {
            notamSource = "source=AppOther";
          }
          String notamAirports = "&airports=$allAirports";
          String notamUrl = notamServer + notamApi + notamSource + notamAirports;

          int timeOut = 20 * _myRequestedAirports.length;
          final response = await http.post(notamUrl).timeout(Duration(seconds: timeOut));

          if (response.statusCode != 200) {
            notamFailed = true;

          } else {
            var timeNow = DateTime.now().toUtc();
            String notamRequestedTime = timeNow.toIso8601String();

            SharedPreferencesModel().setNotamInformation(response.body);
            SharedPreferencesModel().setNotamUserInput(_userSubmitText);
            SharedPreferencesModel().setNotamRequestedAirports(_myRequestedAirports);
            SharedPreferencesModel().setNotamRequestedTime(notamRequestedTime);
          }
        }
      }

      if (wxFailed || notamFailed) {
        throw "error";
      }

    } catch (Exception) {

      String expString = "";
      if (fetchBoth) {
        if (wxFailed && notamFailed) {
          expString = "Fetching failed both for WX and NOTAM, please try again later!";
        } else if (wxFailed) {
          expString = "Fetching failed for WX, but NOTAM were proccessed!";
        } else if (notamFailed) {
          expString = "WEATHER was proceessed, but fetching failed for NOTAM!";
        } else {
          expString = "There was an error with the server or the Internet connection!";
        }
      } else {
        if (wxFailed) {
          expString = "Failed fetching WEATHER, please try again later!";
        } else {
          expString = "There was an error with the server or the Internet connection!";
        }
      }

      widget.hideBottomSheet();
      Scaffold.of(context).showSnackBar(
        SnackBar(
          content: Text(
            expString,
            style: TextStyle(
              color: Colors.black,
            )
          ),
          backgroundColor: Colors.red[100],
          duration: Duration(seconds: 6),
        ),
      );

      // This handles when we show the BottomSheet again
      // This ensures that we wait for the first SnackBar (normally 4 + 1) seconds
      // and then we add another 6 + 1 for the error, but we check
      // previously if the wait has to be increased as the first one has not
      // yet been on screen for 5 seconds
      DateTime finishRequest = DateTime.now();
      int diffTime = finishRequest.difference(startRequest).inSeconds;
      int myWait;
      if (diffTime <= firstSnackTimeNeeded) {
        myWait = firstSnackTimeNeeded - diffTime + 7;   // First SnackBar - time until now + time for the second one
      } else {
        myWait = 7;  // If more time has elapsed, just wait 6 + 1 seconds for the error SnackBar
      }
      Timer(Duration(seconds: myWait), () => widget.showBottomSheet());

      return null;
    }

    // This handles when we show the BottomSheet again
    // and tries to decrease the time if elapse time has already counted
    // for more than 5 seconds (in which case we just show it again)
    DateTime finishRequest = DateTime.now();
    int diffTime = finishRequest.difference(startRequest).inSeconds;
    int myWait = 0;
    if (diffTime < firstSnackTimeNeeded) {
      myWait = (firstSnackTimeNeeded - diffTime).round();
    }
    Timer(Duration(seconds: myWait), () => widget.showBottomSheet());

    return wxExportedJson;
  }


  Future<void> _showSettings() async {
    return showDialog (
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return WeatherOptionsDialog(
          hours: _hoursBefore,
          hoursChangedCallback: _hoursBeforeChanged
        );
      }
    );
  }


  void _hoursBeforeChanged(double newValue) {
      _hoursBefore = newValue.toInt();
  }

  void onMainScrolled() {
    widget.notifyScrollPosition(_myMainScrollController.offset);
  }
}
