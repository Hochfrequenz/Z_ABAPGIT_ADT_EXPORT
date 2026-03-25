" ADT resource application for abapGit package export.
" Pattern taken from https://github.com/abapGit/ADT_Backend
" specifically ZCL_ABAPGIT_RES_REPOS_APP which registers
" ADT resources under /sap/bc/adt/abapgit/.
CLASS zcl_abapgit_adt_exp_app DEFINITION
  PUBLIC
  INHERITING FROM cl_adt_disc_res_app_base
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS if_adt_rest_rfc_application~get_static_uri_path REDEFINITION.

  PROTECTED SECTION.

    METHODS get_application_title REDEFINITION.
    METHODS register_resources REDEFINITION.

  PRIVATE SECTION.

ENDCLASS.



CLASS zcl_abapgit_adt_exp_app IMPLEMENTATION.

  METHOD get_application_title.
    result = 'abapGit Package Export'(001).
  ENDMETHOD.


  METHOD if_adt_rest_rfc_application~get_static_uri_path.
    result = '/sap/bc/adt/abapgit/export' ##NO_TEXT.
  ENDMETHOD.


  METHOD register_resources.
    registry->register_discoverable_resource(
      url             = '/packages'
      handler_class   = 'ZCL_ABAPGIT_ADT_EXP_RES'
      description     = 'Export abapGit Package as ZIP'(002)
      category_scheme = 'http://www.sap.com/adt/categories/abapgit'
      category_term   = 'export' ) ##NO_TEXT.
  ENDMETHOD.

ENDCLASS.
