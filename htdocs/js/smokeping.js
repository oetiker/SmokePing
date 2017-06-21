/*++ from bonsai.js ++ urlObj  +++++++++++++++++++++++++++++++++++++++++*/
function urlObj(url) {
   var urlBaseAndParameters;

   urlBaseAndParameters = url.split("?"); 
   this.urlBase = urlBaseAndParameters[0];
   this.urlParameters = urlBaseAndParameters[1].split(/[;&]/);

   this.getUrlBase = urlObjGetUrlBase;
}

/*++ from bonsai.js ++ urlObjGetUrlBase  +++++++++++++++++++++++++++++++*/

function urlObjGetUrlBase() {
   return this.urlBase;
}


// example with minimum dimensions
var myCropper;

var StartEpoch = 0;
var EndEpoch = 0;



function changeRRDImage(coords,dimensions){

    var SelectLeft = Math.min(coords.x1,coords.x2);

    var SelectRight = Math.max(coords.x1,coords.x2);

    if (SelectLeft == SelectRight)
         return; // abort if nothing is selected.

    var RRDLeft  = 67;        // difference between left border of RRD image and content
    var RRDRight = 26;        // difference between right border of RRD image and content
    var RRDImgWidth  = $('zoom').getDimensions().width;       // Width of the Smokeping RRD Graphik
    var RRDImgUsable = RRDImgWidth - RRDRight - RRDLeft;  
    var form = $('range_form');   
    
    if (StartEpoch == 0)
        StartEpoch = +$F('epoch_start');
   
    if (EndEpoch  == 0)
        EndEpoch = +$F('epoch_end');

    var DivEpoch = EndEpoch - StartEpoch; 

    var Target = $F('target');
    var Hierarchy = $F('hierarchy');

    // construct Image URL
    var myURLObj = new urlObj(document.URL); 

    var myURL = myURLObj.getUrlBase(); 

    // Generate Selected Range in Unix Timestamps
    var LeftFactor = 1;
    var RightFactor = 1;

    if (SelectLeft < RRDLeft)
        LeftFactor = 10;        

    StartEpoch = Math.floor(StartEpoch + (SelectLeft  - RRDLeft) * DivEpoch / RRDImgUsable * LeftFactor );

    if (SelectRight > RRDImgWidth - RRDRight)
        RightFactor = 10;

    EndEpoch  =  Math.ceil(EndEpoch + (SelectRight - (RRDImgWidth - RRDRight) ) * DivEpoch / RRDImgUsable * RightFactor);


    $('zoom').src = myURL + '?displaymode=a;start=' + StartEpoch + ';end=' + EndEpoch + ';target=' + Target + ';hierarchy=' + Hierarchy;    

    myCropper.setParams();

};

Event.observe( 
    window,
    'load',
    function() {
        $('menu-button').observe('click', function (e) {
            $('body').toggleClassName('sidebar-hidden');
            Event.stop(e);
        });
        if ($('zoom') != null) {
            myCropper = new Cropper.Img(
                'zoom',
                {
                    minHeight: $('zoom').getDimensions().height,
                    maxHeight: $('zoom').getDimensions().height,
                    onEndCrop: changeRRDImage
                }
            )
        }
    }
);

