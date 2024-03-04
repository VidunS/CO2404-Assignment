import 'package:flutter__assignment/apikey/apikey.dart';

String trendingmoviesurl =
    'https://api.themoviedb.org/3/trending/movie/day?api_key=$apikey';
String nowplayingmoviesurl =
    'https://api.themoviedb.org/3/movie/now_playing?api_key=$apikey';
String upcomingmoviesurl =
    'https://api.themoviedb.org/3/movie/upcoming?api_key=$apikey';
String currentYear = DateTime.now().year.toString();
String bestmoviesurl =
    'https://api.themoviedb.org/3/discover/movie?api_key=$apikey&primary_release_year=$currentYear&sort_by=popularity.desc';
String highestgrossingurl =
    'https://api.themoviedb.org/3/discover/movie?api_key=$apikey&sort_by=revenue.desc';
String childrenmoviesurl =
    'https://api.themoviedb.org/3/discover/movie?api_key=$apikey&sort_by=revenue.desc&adult=false&with_genres=16';
String popularmoviesurl =
    'https://api.themoviedb.org/3/movie/popular?api_key=$apikey';
String topratedmoviesurl =
    'https://api.themoviedb.org/3/movie/top_rated?api_key=$apikey';
String populartvurl = 'https://api.themoviedb.org/3/tv/popular?api_key=$apikey';
String topratedtvurl =
    'https://api.themoviedb.org/3/tv/top_rated?api_key=$apikey';
 