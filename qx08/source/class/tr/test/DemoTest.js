/* ************************************************************************

   Copyright:

   License:

   Authors:

************************************************************************ */

/**
 * This class demonstrates how to define unit tests for your application.
 *
 * Execute <code>generate.py test</code> to generate a testrunner application 
 * and open it from <tt>test/index.html</tt>
 *
 * The methods that contain the tests are instance methods with a 
 * <code>test</code> prefix. You can create an arbitrary number of test 
 * classes like this one. They can be organized in a regular class hierarchy, 
 * i.e. using deeper namespaces and a corresponding file structure within the 
 * <tt>test</tt> folder.
 */
qx.Class.define("tr.test.DemoTest",
{
  extend : qx.dev.unit.TestCase,

  members :
  {
    /*
    ---------------------------------------------------------------------------
      TESTS
    ---------------------------------------------------------------------------
    */
  
    /**
     * Here are some simple tests
     */
    testSimple : function()
    {
      this.assertEquals(4, 3+1, "This should never fail!");
      this.assertFalse(false, "Can false be true?!");
    },

    /**
     * Here are some more advanced tests
     */
    testAdvanced: function () 
    {
      var a = 3;
      var b = a;
      this.assertIdentical(a, b, "A rose by any other name is still a rose");
      this.assertInRange(3, 1, 10, "You must be kidding, 3 can never be outside [1,10]!");
    }
  }
});
