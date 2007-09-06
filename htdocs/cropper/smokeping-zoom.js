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

    if (StartEpoch == 0) 
        StartEpoch = $('epoch_start').value;
    if (EndEpoch  == 0)
        EndEpoch = $('epoch_end').value;
    var DivEpoch = EndEpoch - StartEpoch; 

    var Target = $('target').value;

    // Generate Selected Range in Unix Timestamps

    StartEpoch = Math.floor(StartEpoch + (((SelectLeft  - RRDLeft) / RRDImgUsable ) * DivEpoch));
    EndEpoch  = Math.ceil(StartEpoch + (((SelectRight - RRDLeft) / RRDImgUsable ) * DivEpoch));

    // construct Image URL

    $('zoom').src = myURL + "?displaymode=a;start=" + genStart+ ";end=" + genEnd + ";target=" + Target;
    myCropper.setParams();

};

Event.observe( 
           window, 
           'load', 
           function() { 
               myCropper = new Cropper.Img( 
                               'zoom', 
                                        { 
                                                minHeight: $('zoom').getDimensions().height,
                                                maxHeight: $('zoom').getDimensions().height,
                                                onEndCrop: changeRRDImage
                                        } 
                                ) 
                   }
           );

