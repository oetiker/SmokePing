<!--

/*
 * This code replaces images in the smokeping website with ajax
 *
 * The jquery toolkit (version 1.1.3.1) was used for platform
 * independency. The URL parsing part was taken from the 
 * bonsaj.js script.
 *
 * Copyright (c) 2007 Roman Plessl <roman.plessl@oetiker.ch>
 * Dual licensed under the MIT (MIT-LICENSE.txt)
 * and GPL (GPL-LICENSE.txt) licenses.
 *
 * $Date: 2007-08-15 17:14:56 +0200 $
 * $Rev: 36 $
 * 
 */

/*++ from bonsai.js ++ urlObj  +++++++++++++++++++++++++++++++++++++++++*/
function urlObj(url) {
   var urlBaseAndParameters;

   urlBaseAndParameters = url.split("?"); 
   this.urlBase = urlBaseAndParameters[0];
   this.urlParameters = urlBaseAndParameters[1].split(";");

   this.getUrlBase = urlObjGetUrlBase;
   this.getUrlParameterValue = urlObjGetUrlParameterValue;
}

/*++ from bonsai.js ++ urlObjGetUrlBase  +++++++++++++++++++++++++++++++*/

function urlObjGetUrlBase() {
   return this.urlBase;
}

/*++ form bonsai.js ++  urlObjGetUrlParameterValue  +++++++++++++++++++++*/

function urlObjGetUrlParameterValue(parameter) {
   var i;
   var fieldAndValue;
   var value;

   i = 0;
   while (this.urlParameters [i] != undefined) {
      fieldAndValue = this.urlParameters[i].split("=");
      if (fieldAndValue[0] == parameter) {
         value = fieldAndValue[1];
      } 
    i++;
    }
    return value;
}

/*++++++++++++++++++++  isoDateToJS  +++++++++++++++++++++++++++++++++++++*/
function ISODateToJS(rawisodate) {
   var decode = decodeURI(rawisodate);
  if (decode == "now") {
       return new Date();
   } 
   else  {
      var M = decode.match(/(\d\d\d\d).(\d\d).(\d\d).(\d\d).(\d\d)/)
      var date = new Date(M[1], M[2]-1, M[3], M[4], M[5], "00")
      return date;
   }
}

/*++++++++++++++++++++++ JSToisoDate ++++++++++++++++++++++++++++++++++++++*/
function JSToISODate(mydate) {
   var isodate = mydate.getFullYear() + "-";
   if ((mydate.getMonth() + 1) < 10)   { isodate = isodate + "0"; } 
   isodate = isodate + (mydate.getMonth() + 1) + "-";
   if (mydate.getDate() < 10)           { isodate = isodate + "0"; }  
   isodate = isodate + mydate.getDate() + " ";
   if (mydate.getHours() < 10)         { isodate = isodate + "0"; }   
   isodate = isodate + mydate.getHours() + ":";
   if (mydate.getMinutes() < 10)       { isodate = isodate + "0"; } 
   isodate = isodate + mydate.getMinutes();
   return encodeURI(isodate);
}
  
$(document).ready(function() { 

    mySelectTop     = 0;
    mySelectLeft    = 0;
    mySelectRight   = 0;
    mySelectBottom  = 0;

    myImgTop     = 0;
    myImgLeft    = 0;
    myImgRight   = 0;
    myImgBottom  = 0;  
 
    RRDLeftDiff  = 68;        // difference between left border of RRD image and content
    RRDRightDiff = 33;        // difference between right border of RRD image and content
    RRDImgWidth  = 697;       // Width of the Smokeping RRD Graphik
    RRDImgUsable = 596;       // 598 = 697 - 68 - 33;

    mySelectTop     = 0;
    mySelectLeft    = 0;
    mySelectRight   = 0;
    mySelectBottom  = 0;

    StartDateString = 0;
    EndDateString  = 0;
   
    $("div.zoom").mousedown(function() {

         var rrdimg   = $("div.zoom").children("img");
         myImgTop     = rrdimg.get(0).y;
         myImgLeft    = rrdimg.get(0).x;
         myImgRight   = myImgLeft + rrdimg.get(0).width;
         myImgBottom  = myImgTop + rrdimg.get(0).height;
 
     });

    $("div.zoom").Selectable({
                accept : 'selectableitem',
                opacity : 0.2,
                selectedclass : 'selecteditem',
                helperclass : 'selecthelper'
    });   

});

// will be started by modified iSelect (StopApply Function)
function changeRRDImage(){

         var oldimg = $("div.zoom").children("img");

         myURLObj = new urlObj(document.URL); 

         // parse start and stop parameter from URL  
         var myURL = myURLObj.getUrlBase(); 
         var myRawStartDate = (StartDateString != 0) ? StartDateString : myURLObj.getUrlParameterValue("start");
         var myRawStopDate  = (EndDateString != 0) ? EndDateString : myURLObj.getUrlParameterValue("end");   
         var myRawTarget    = myURLObj.getUrlParameterValue("target"); 

         var myParsedStartDate = ISODateToJS(myRawStartDate);
         myParsedStartEpoch = Math.floor(myParsedStartDate.getTime()/1000.0);
 
         var myParsedStopDate  = ISODateToJS(myRawStopDate);
         myParsedStopEpoch = Math.floor(myParsedStopDate.getTime()/1000.0);   
 
         myParsedDivEpoch = myParsedStopEpoch - myParsedStartEpoch; 

         var mySerialDate = new Date();
         var mySerial = mySerialDate.getTime();

         // Generate Selected Range in Unix Timestamps
         var genStart = myParsedStartEpoch + (((mySelectLeft  - RRDLeftDiff) / RRDImgUsable ) * myParsedDivEpoch);
         var genStop  = myParsedStartEpoch + (((mySelectRight - RRDLeftDiff) / RRDImgUsable ) * myParsedDivEpoch);

         var floorGenStart = Math.floor(genStart);
         var floorGenStop  = Math.floor(genStop);

         var StartDate = new Date(floorGenStart*1000); 
         var StopDate  = new Date(floorGenStop*1000);

         // floor to last full minute
         var MinuteGenStart = ( Math.floor(floorGenStart / 60) * 60 );
         var MinuteGenStop  = ( Math.floor(floorGenStop  / 60) * 60 );

         // create new image based on old image and fetched data
         var newimg = new Image();
         newimg = oldimg;
 
         StartDateString = JSToISODate(StartDate);
         EndDateString   = JSToISODate(StopDate);

         // construct Image URL
         myGraph = "img/__navcache/" + mySerial + "_" + MinuteGenStop + "_" + MinuteGenStart + ".png";

         // Fetch image with ajax
         var result = $.get(myURL + "?displaymode=a;start=" + StartDateString+ ";end=" + EndDateString + ";target=" + myRawTarget + ";serial=" + mySerial,
             function(){
                // replacement image with AJAX
                newimg.attr("src", myGraph);                                  
             });
};

