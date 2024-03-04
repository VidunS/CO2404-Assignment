import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter__assignment/apikey/apikey.dart';

class Movies extends StatefulWidget {
  const Movies({super.key});

  @override
  State<Movies> createState() => _MoviesState();
}

class _MoviesState extends State<Movies> {
//   List<Map<String.dynamic>> nowplaying = [] ;
//   List<Map<String.dynamic>> bestmovies = [] ;
//   List<Map<String.dynamic>> highestgrossing = [] ;
//   List<Map<String.dynamic>>  = [] ;

  // String nowplayingmoviesurl =
  //   'https://api.themoviedb.org/3/movie/now_playing?api_key=$apikey';
  // String bestmoviesurl =
  //   'https://api.themoviedb.org/3/discover/movie?api_key=$apikey&primary_release_year=$currentYear&sort_by=popularity.desc';
  // String highestgrossingurl =
  //   'https://api.themoviedb.org/3/discover/movie?api_key=$apikey&sort_by=revenue.desc';
  // String childrenmoviesurl =
  //   'https://api.themoviedb.org/3/discover/movie?api_key=$apikey&sort_by=revenue.desc&adult=false&with_genres=16';

  List<Map<String, dynamic>> nowplayingmovies = [];

  var nowplayingmoviesurl =
      'https://api.themoviedb.org/3/movie/now_playing?api_key=$apikey';

  Future<void> moviesfunction() async {
    var nowplayingresponse = await http.get(Uri.parse(nowplayingmoviesurl));
    if (nowplayingresponse.statusCode == 200) {
      var tempdata = jsonDecode(nowplayingresponse.body);
      var nowplayingjson = tempdata['results'];
      for (var i = 0; i < nowplayingjson.length; i++) {
        nowplayingmovies.add({
          "name": nowplayingjson[i]["title"].toString(),
          "poster_path": nowplayingjson[i]["poster_path"] != null
              ? nowplayingjson[i]["poster_path"].toString()
              : "",
          "vote_average": nowplayingjson[i]["vote_average"] != null
              ? nowplayingjson[i]["vote_average"].toString()
              : "",
          "Date": nowplayingjson[i]["release_date"] != null
              ? nowplayingjson[i]["release_date"].toString()
              : "",
          "id": nowplayingjson[i]["id"].toString(),
        });
      }
    } else {
      print(nowplayingresponse.statusCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: moviesfunction(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return Center(
                child: CircularProgressIndicator(color: Colors.amber.shade400));
          else {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                      padding: const EdgeInsets.only(
                          left: 10.0, top: 15, bottom: 40),
                      child: Text("What's on at the cinema")),
                  Container(
                      height: 250,
                      child: ListView.builder(
                          physics: BouncingScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          itemCount: nowplayingmovies.length,
                          itemBuilder: (context, index) {
                            return GestureDetector(
                                onTap: () {},
                                child: Container(
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(15),
                                        image: DecorationImage(
                                            image: NetworkImage(
                                                'https://image.tmdb.org/t/p/w500${nowplayingmovies[index]['poster_path']}'),
                                            fit: BoxFit.cover)),
                                    margin: EdgeInsets.only(left: 13),
                                    width: 170,
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 2, left: 6),
                                              child: Text(
                                                  nowplayingmovies[index]
                                                      ['Date'])),
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 2, right: 6))
                                        ])));
                          })),
                ]);
          }
        });
  }
}
