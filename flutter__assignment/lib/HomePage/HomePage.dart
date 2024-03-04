import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter__assignment/apilinks/allapi.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter__assignment/HomePage/SectionPage/Movies.dart';
import 'package:flutter__assignment/HomePage/SectionPage/Upcoming.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> trendinglist = [];

  Future<void> trendinglisthome() async {
    String apikey = 'dfed8105e4d8334d830ab0a9fc6b16d9';
    String trendingmoviesurl =
        'https://api.themoviedb.org/3/trending/movie/day?api_key=$apikey';
    var trendingweekresponse = await http.get(Uri.parse(trendingmoviesurl));
    if (trendingweekresponse.statusCode == 200) {
      var tempdata = jsonDecode(trendingweekresponse.body);
      var trendingweekjson = tempdata['results'];
      for (var i = 0; i < trendingweekjson.length; i++) {
        trendinglist.add({
          'id': trendingweekjson[i]['id'],
          'poster_path': trendingweekjson[i]['poster_path'],
          'vote_average': trendingweekjson[i]['vote_average'],
          'media_type': trendingweekjson[i]['meedia_type'],
          'indexno': i,
        });
      }
    }
  }

  int uval = 1;
  @override
  Widget build(BuildContext context) {
    TabController _tabController = TabController(length: 2, vsync: this);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            centerTitle: true,
            //automaticallyImplyLeading: false
            toolbarHeight: 60,
            pinned: true,
            expandedHeight: MediaQuery.of(context).size.height * 0.5,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: FutureBuilder(
                future: trendinglisthome(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return CarouselSlider(
                      options: CarouselOptions(
                          viewportFraction: 1,
                          autoPlay: true,
                          autoPlayInterval: Duration(seconds: 2),
                          height: MediaQuery.of(context).size.height),
                      items: trendinglist.map((i) {
                        return Builder(builder: (BuildContext context) {
                          return GestureDetector(
                              onTap: () {},
                              child: GestureDetector(
                                  onTap: () {},
                                  child: Container(
                                      width: MediaQuery.of(context).size.width,
                                      decoration: BoxDecoration(
                                        //color: Colors.amber,
                                        image: DecorationImage(
                                            colorFilter: ColorFilter.mode(
                                                Colors.black.withOpacity(0.3),
                                                BlendMode.darken),
                                            image: NetworkImage(
                                                'https://image.tmdb.org/t/p/w500${i['poster_path']}'),
                                            fit: BoxFit.fill),
                                      ))));
                        });
                      }).toList(),
                    );
                  } else {
                    return Center(
                        child: CircularProgressIndicator(
                      color: Colors.amber,
                    ));
                  }
                },
              ),
            ),

            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Trending',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 16)),
                SizedBox(width: 10),
              ],
            ),
          ),
          SliverList(
              delegate: SliverChildListDelegate([
            Center(
              child: Text("Sample Text"),
            ),
            Container(
              height: 45,
              width: MediaQuery.of(context).size.width,
              child: TabBar(
                physics: BouncingScrollPhysics(),
                labelPadding: EdgeInsets.symmetric(horizontal: 25),
                isScrollable: true,
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.amber.withOpacity(0.4),
                ),
                tabs: [
                  Tab(child: Text('Movies')),
                  Tab(child: Text('Upcoming')),
                ],
              ),
            ),
            Container(
              height: 1050,
              child: TabBarView(
                controller: _tabController,
                children: [
                  Movies(),
                  Upcoming(),
                ],
              ),
            )
          ]))
        ],
      ),
    );
  }
}
