/*++ from bonsai.js ++ urlObj  +++++++++++++++++++++++++++++++++++++++++*/
function urlObj(url) {
   var urlBaseAndParameters;

   urlBaseAndParameters = url.split("?"); 
   this.urlBase = urlBaseAndParameters[0];
   this.urlParameters = urlBaseAndParameters[1].split(/[;&]/);

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
   var decode = decodeURIComponent(rawisodate);
  if (decode == "now") {
       return new Date();
   } 
   else  {
      var M = decode.match(/(\d\d\d\d)-(\d\d?)-(\d\d?)[+ ](\d\d?):(\d\d?)/)
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

// example with minimum dimensions
var myCropper;


// will be started by modified iSelect (StopApply Function)
var StartDateString = 0;
var EndDateString = 0;

function changeRRDImage(coords,dimensions){

    var RRDLeftDiff  = 50;        // difference between left border of RRD image and content
    var RRDRightDiff = 30;        // difference between right border of RRD image and content
    var RRDImgWidth  = 697;       // Width of the Smokeping RRD Graphik
    var RRDImgUsable = 596;       // 598 = 697 - 68 - 33;
    var mySelectLeft = coords.x1;
    var mySelectRight = coords.x2;
        if (mySelectLeft == mySelectRight) return; // abort if nothing is selected.

         myURLObj = new urlObj(document.URL); 

         // parse start and stop parameter from URL  
         var myURL = myURLObj.getUrlBase(); 
         var myRawStartDate = (StartDateString != 0) ? StartDateString : myURLObj.getUrlParameterValue("start");
         var myRawStopDate  = (EndDateString != 0) ? EndDateString : myURLObj.getUrlParameterValue("end");   
         var myRawTarget    = myURLObj.getUrlParameterValue("target"); 

         var myParsedStartDate = ISODateToJS(myRawStartDate);
         var myParsedStartEpoch = Math.floor(myParsedStartDate.getTime()/1000.0);
 
         var myParsedStopDate  = ISODateToJS(myRawStopDate);
         var myParsedStopEpoch = Math.floor(myParsedStopDate.getTime()/1000.0);   
 
         var myParsedDivEpoch = myParsedStopEpoch - myParsedStartEpoch; 

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

         StartDateString = JSToISODate(StartDate);
         EndDateString   = JSToISODate(StopDate);

         // construct Image URL
         $('zoom').src = myURL + "?displaymode=a;start=" + StartDateString+ ";end=" + EndDateString + ";target=" + myRawTarget + ";serial=" + mySerial;
         myCropper.setParams();
};

Event.observe( 
           window, 
           'load', 
           function() { 
               myCropper = new Cropper.Img( 
                               'zoom', 
                                        { 
                                                minHeight: 321,
                                                maxHeight: 321,
                                                onEndCrop: changeRRDImage
                                        } 
                                ) 
                   }
           );

