module Main exposing (..)

import Array
import Browser
import Grid
import Html exposing (Html, br, button, div, img, text)
import Html.Attributes exposing (class, src, style)
import Html.Events exposing (onClick)
import String exposing (fromInt)
import Time
import WaveFunctionCollapse exposing (..)



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


init : () -> ( Model, Cmd Msg )
init _ =
    ( { propGrid = propGrid 15 15
      , openSteps = []
      , mode = Manual
      , speed = 200
      }
    , Cmd.none
    )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Pick nextMode pos tileId ->
            ( { model
                | openSteps = [ PickTile pos tileId ]
                , mode = nextMode
              }
            , Cmd.none
            )

        Step ->
            propagate model

        Play ->
            ( { model | mode = AutoStep }
            , Cmd.none
            )

        Faster ->
            ( { model | speed = model.speed // 2 }
            , Cmd.none
            )

        Slower ->
            ( { model | speed = model.speed * 2 }
            , Cmd.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions { mode, speed } =
    case mode of
        Manual ->
            Sub.none

        AutoStep ->
            Time.every (toFloat speed) (\_ -> Step)



-- VIEW


view : Model -> Html Msg
view model =
    let
        modeView =
            case model.mode of
                AutoStep ->
                    text "Playing"

                Manual ->
                    text "Stopped"
    in
    div []
        [ div []
            [ button [ onClick <| Step ] [ text "step" ]
            , button [ onClick Play ] [ text "play ", text <| fromInt model.speed ]
            , button [ onClick Slower ] [ text "-" ]
            , button [ onClick Faster ] [ text "+" ]
            , modeView
            ]
        , viewPropGrid model.propGrid
        , viewTiles
        ]


viewTiles : Html msg
viewTiles =
    let
        f i { filename } =
            div [ style "background-image" ("url(assets/tiles/" ++ filename ++ ")") ] [ text <| fromInt i, br [] [], text filename ]
    in
    div [ class "examples" ] <| List.indexedMap f tileImages


viewPropGrid : PropagationGrid -> Html Msg
viewPropGrid grid =
    let
        rows =
            Grid.rows grid

        mkNum options pos i =
            let
                attrs =
                    if List.member i options then
                        [ onClick (Pick Manual pos i) ]

                    else
                        [ class "off" ]
            in
            div attrs [ text <| fromInt i ]

        viewTile row col propTile =
            case propTile of
                Fixed i ->
                    let
                        { filename } =
                            tileById i
                    in
                    div [ style "background-image" ("url(assets/tiles/" ++ filename ++ ")") ] []

                Superposition options ->
                    div [ class "superposition" ] <|
                        List.map (mkNum options ( col, row )) <|
                            List.range 0 (List.length tileImages)

        viewRow row tiles =
            div [ class "row" ] <| Array.toList <| Array.indexedMap (viewTile row) tiles
    in
    div [] <| Array.toList <| Array.indexedMap viewRow rows