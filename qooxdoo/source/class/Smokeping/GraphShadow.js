/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * The data representation of a Smokeping Graph
 */

qx.Class.define('Smokeping.GraphShadow', 
{
    extend: qx.core.Object, 
    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */
    construct : function() {
        this.base(arguments);
    },

    /*
    *****************************************************************************
     MEMBERS
    *****************************************************************************
    */
    properties: {
        /** Width of the graph canvas in pixels */
        width :
        {
          check : "Number",
          nullable : true,
          themeable : false
        },
        /** height of the graph canvas in pixels */
        height :
        {
          check : "Number",
          nullable : true,
          themeable : false
        },
        /** start of the graph in seconds since 1970 */
        start :
        {
          check : "Number",
          nullable : true,
          themeable : false
        },
        /** end of the graph in seconds since 1970 */
        end :
        {
          check : "Number",
          nullable : true,
          themeable : false
        },
        /** upper border of the graph */
        top :
        {
          check : "Number",
          nullable : true,
          themeable : false
        }, 
        /** bottom border of the graph */
        bottom :
        {
          check : "Number",
          nullable : true,
          themeable : false
        },

        /** url to the cgi which produces the graphs */
        cgi :
        {
          check : "String",
          nullable : true,
          themeable : false
        },

        /** which data source should we use for the graph */
        data :
        {
          check : "String",
          nullable : true,
          themeable : false
        }
    },
    members: {
        getSrc: function(){
            with(this){
                return getCgi()+'?g='+getData()+';w='+getWidth()+';h='+getHeight()+';s='+getStart()+';e='+getEnd()+';t='+getTop()+';b='+getBottom();
            }
        }
    }
});
 
