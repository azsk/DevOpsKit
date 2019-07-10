using System;
using System.Collections.Generic;
using System.Text;

namespace AzSK.ARMChecker.Lib
{
    class RegExpressionSingleTokenControlData
    {
        public ControlDataMatchType Type { get; set; }
        // Allow, NotAllow
        public string Pattern { get; set; }
        public bool IsCaseSensitive { get; set; }
    }
}
