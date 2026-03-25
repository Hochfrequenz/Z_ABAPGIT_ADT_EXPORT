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
        VALUE(rv_package) TYPE devclass
      RAISING
        cx_adt_rest.

    METHODS validate_package_exists
      IMPORTING
        iv_package TYPE devclass
      RAISING
        cx_adt_rest.

ENDCLASS.



CLASS zcl_abapgit_adt_exp_res IMPLEMENTATION.

  METHOD get.

    DATA lv_zip           TYPE xstring.
    DATA ls_local_settings TYPE zif_abapgit_persistence=>ty_repo-local_settings.
    DATA lo_dot_abapgit   TYPE REF TO zcl_abapgit_dot_abapgit.
    DATA lv_folder_logic  TYPE string.
    DATA lv_main_lang     TYPE string.

    " Read and validate package parameter
    DATA(lv_package) = get_package_name( request ).
    validate_package_exists( lv_package ).

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
        RAISE EXCEPTION TYPE cx_adt_rest
          EXPORTING
            textid = cx_adt_rest=>create_textid_from_msg_params(
                       iv_msg_id = '00'
                       iv_msg_no = '001'
                       iv_par1   = lx_error->get_text( ) )
            status = cl_rest_status_code=>gc_server_error_internal.
    ENDTRY.

    IF lv_zip IS INITIAL.
      RAISE EXCEPTION TYPE cx_adt_rest
        EXPORTING
          textid = cx_adt_rest=>create_textid_from_msg_params(
                     iv_msg_id = '00'
                     iv_msg_no = '001'
                     iv_par1   = 'Serialization returned empty result' )
          status = cl_rest_status_code=>gc_server_error_internal.
    ENDIF.

    " Return binary ZIP data via the inner HTTP response
    DATA(lo_inner_response) = response->get_inner_rest_response( ).
    DATA(lo_http_response)  = lo_inner_response->get_server( )->response.
    lo_http_response->set_header_field(
      name  = if_http_header_fields=>content_type
      value = 'application/zip' ).
    lo_http_response->set_header_field(
      name  = 'Content-Disposition'
      value = |attachment; filename="{ lv_package }.zip"| ).
    lo_http_response->set_data( lv_zip ).
    response->set_status( cl_rest_status_code=>gc_success_ok ).

  ENDMETHOD.


  METHOD get_package_name.

    DATA lv_package TYPE string.

    io_request->get_uri_query_parameter(
      EXPORTING name  = 'package'
      IMPORTING value = lv_package ).

    IF lv_package IS INITIAL.
      RAISE EXCEPTION TYPE cx_adt_rest
        EXPORTING
          textid = cx_adt_rest=>create_textid_from_msg_params(
                     iv_msg_id = '00'
                     iv_msg_no = '001'
                     iv_par1   = 'Missing required parameter: package' )
          status = cl_rest_status_code=>gc_client_error_bad_request.
    ENDIF.

    rv_package = to_upper( lv_package ).

  ENDMETHOD.


  METHOD validate_package_exists.

    SELECT SINGLE devclass FROM tdevc
      INTO @DATA(lv_dummy)
      WHERE devclass = @iv_package.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_adt_rest
        EXPORTING
          textid = cx_adt_rest=>create_textid_from_msg_params(
                     iv_msg_id = '00'
                     iv_msg_no = '001'
                     iv_par1   = |Package { iv_package } does not exist| )
          status = cl_rest_status_code=>gc_client_error_not_found.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
