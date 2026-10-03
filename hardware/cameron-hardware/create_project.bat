subst V: "%CD%"
cd /d V:\

vivado -mode batch -source project_recreate.tcl

:: subst V: "%CD%"
:: cd /d V:\
::vivado -mode batch -source create_project.tcl

:: write_bd_tcl -force -include_layout ./top_design.tcl