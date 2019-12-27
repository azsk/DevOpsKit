using System;
using System.Collections.Generic;
using System.Text;

namespace AzSK.ARMChecker.Lib
{
    class StringMultiTokenControlData
    {
        public ControlDataMatchType Type { get; set; }
        public string[] Value { get; set; }
        public bool IsCaseSensitive { get; set; }
        public string IfNoPropertyFound { get; set; }
    }
}
