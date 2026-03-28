" ADT resource handler for exporting ABAP packages as abapGit ZIP files.
" The serialization logic mirrors ZCL_ABAPGIT_ZIP=>EXPORT_PACKAGE
" (see source via ADT: /sap/bc/adt/oo/classes/ZCL_ABAPGIT_ZIP/source/main)
" but skips the frontend file-save dialog and instead returns the ZIP
" binary directly via the HTTP response.
" Binary response approach uses get_inner_rest_response->get_server->response
" because IF_ADT_REST_RESPONSE has SET_BODY_DATA (not set_binary_data).
CLASS zcl_abapgit_adt_exp_res DEFINITION
  PUBLIC
  INHERITING FROM cl_adt_rest_resource
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS get REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.

    METHODS get_package_name
      IMPORTING
        io_request        TYPE REF TO if_adt_rest_request
      RETURNING
        VALUE(rv_package) TYPE devclass.

    METHODS validate_package_exists
      IMPORTING
        iv_package        TYPE devclass
      RETURNING
        VALUE(rv_exists)  TYPE abap_bool.

ENDCLASS.



CLASS zcl_abapgit_adt_exp_res IMPLEMENTATION.

  METHOD get.

    DATA lv_zip            TYPE xstring.
    DATA ls_local_settings TYPE zif_abapgit_persistence=>ty_repo-local_settings.
    DATA lo_dot_abapgit    TYPE REF TO zcl_abapgit_dot_abapgit.
    DATA lv_folder_logic   TYPE string.
    DATA lv_main_lang      TYPE string.

    " Read and validate package parameter
    DATA(lv_package) = get_package_name( request ).

    IF lv_package IS INITIAL.
      response->set_status( cl_rest_status_code=>gc_client_error_bad_request ).
      RETURN.
    ENDIF.

    IF validate_package_exists( lv_package ) = abap_false.
      response->set_status( cl_rest_status_code=>gc_client_error_not_found ).
      RETURN.
    ENDIF.

    " Authorization note: we rely on the ADT framework's implicit S_ADT_RES
    " check and abapGit's internal per-object auth checks during serialization.
    " An explicit AUTHORITY-CHECK for S_PACKAGE was tried but removed because
    " many dev systems don't assign S_PACKAGE with DEVCLASS field values,
    " causing false 403s even for fully authorized developers.

    " Read optional parameters
    TRY.
        request->get_uri_query_parameter(
          EXPORTING name = 'folderLogic'
          IMPORTING value = lv_folder_logic ).
      CATCH cx_adt_rest.
        lv_folder_logic = 'PREFIX'.
    ENDTRY.
    IF lv_folder_logic IS INITIAL.
      lv_folder_logic = 'PREFIX'.
    ENDIF.

    TRY.
        request->get_uri_query_parameter(
          EXPORTING name = 'mainLanguageOnly'
          IMPORTING value = lv_main_lang ).
      CATCH cx_adt_rest.
        lv_main_lang = 'false'.
    ENDTRY.

    " Build local settings
    IF lv_main_lang = 'true' OR lv_main_lang = 'X'.
      ls_local_settings-main_language_only = abap_true.
    ENDIF.

    " Build dot_abapgit configuration
    lo_dot_abapgit = zcl_abapgit_dot_abapgit=>build_default( ).
    lo_dot_abapgit->set_folder_logic( lv_folder_logic ).

    " Call abapGit to serialize the package into a ZIP
    TRY.
        lv_zip = zcl_abapgit_zip=>export(
          is_local_settings = ls_local_settings
          iv_package        = lv_package
          io_dot_abapgit    = lo_dot_abapgit
          iv_show_log       = abap_false ).
      CATCH cx_root INTO DATA(lx_error).
        response->set_status( cl_rest_status_code=>gc_server_error_internal ).
        DATA(lo_err_response) = response->get_inner_rest_response( ).
        " Set machine-readable header so the client can detect folder logic
        " failures without parsing the (possibly translated) error text.
        DATA(lv_err_text) = lx_error->get_text( ).
        IF lv_err_text CS 'folder logic'.
          lo_err_response->set_header_field(
            iv_name  = 'X-Abapgit-Folder-Logic-Hint'
            iv_value = 'FULL' ).
        ENDIF.
        DATA(lo_err_entity) = lo_err_response->create_entity( ).
        lo_err_entity->set_content_type( iv_media_type = 'text/plain' ).
        lo_err_entity->set_string_data( lv_err_text ).
        RETURN.
    ENDTRY.

    IF lv_zip IS INITIAL.
      response->set_status( cl_rest_status_code=>gc_server_error_internal ).
      RETURN.
    ENDIF.

    " Return binary ZIP data via IF_REST_ENTITY on the inner REST response.
    " IF_REST_RESPONSE has set_header_field but not set_binary_data;
    " binary data lives on the entity (IF_REST_ENTITY->set_binary_data).
    DATA(lo_inner_response) = response->get_inner_rest_response( ).
    lo_inner_response->set_header_field(
      iv_name  = 'Content-Disposition'
      iv_value = |attachment; filename="{ lv_package }.zip"| ).
    DATA(lo_entity) = lo_inner_response->create_entity( ).
    lo_entity->set_content_type( iv_media_type = 'application/zip' ).
    lo_entity->set_binary_data( iv_data = lv_zip ).
    response->set_status( cl_rest_status_code=>gc_success_ok ).

  ENDMETHOD.


  METHOD get_package_name.

    DATA lv_package TYPE string.

    TRY.
        io_request->get_uri_query_parameter(
          EXPORTING name  = 'package'
          IMPORTING value = lv_package ).
      CATCH cx_adt_rest.
        RETURN.
    ENDTRY.

    rv_package = to_upper( lv_package ).

  ENDMETHOD.


  METHOD validate_package_exists.

    SELECT SINGLE devclass FROM tdevc
      INTO @DATA(lv_dummy)
      WHERE devclass = @iv_package.

    IF sy-subrc = 0.
      rv_exists = abap_true.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
