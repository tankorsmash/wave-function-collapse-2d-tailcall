module WaveFunctionCollapse exposing
    ( Direction(..)
    , Model
    , PropagationTile(..)
    , TilesDefinition
    , done
    , init
    , pickTile
    , propagate
    , solve
    , stopped
    , tileById
    , viewPropGrid
    )

import Array
import Grid exposing (Grid)
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Random exposing (Seed)
import String exposing (fromInt)


type Model tileT socketT
    = Model (ModelDetails tileT socketT)


pickTile : Pos -> TileId -> Model tileT socketT -> Model tileT socketT
pickTile pos tileId (Model model) =
    Model
        { model
            | openSteps = PickTile pos tileId :: model.openSteps
        }


stopped : Model tileT socketT -> Bool
stopped (Model { openSteps }) =
    List.isEmpty openSteps


done : Model tileT socketT -> Bool
done ((Model { propGrid }) as model) =
    let
        f t onlyFixedTiles =
            case t of
                Superposition _ ->
                    False

                Fixed _ ->
                    onlyFixedTiles
    in
    stopped model && Grid.foldr f True propGrid


solve : Model tileT socketT -> Model tileT socketT
solve model =
    if done model then
        model

    else
        solve <| propagate model


propagate : Model tileT socketT -> Model tileT socketT
propagate ((Model modelDetails) as model) =
    case modelDetails.openSteps of
        step :: otherSteps ->
            let
                ( additionalSteps, nextGrid ) =
                    processStep modelDetails step modelDetails.propGrid
            in
            Model
                { modelDetails
                    | propGrid = nextGrid
                    , openSteps = otherSteps ++ additionalSteps
                }

        [] ->
            if not (done model) then
                let
                    ( randomPick, nextSeed ) =
                        Random.step (randomTileAndTileIdGen modelDetails) modelDetails.seed

                    withPick =
                        pickRandom randomPick modelDetails
                in
                Model
                    { withPick | seed = nextSeed }

            else
                model


type alias TilesDefinition tileT socketT =
    { defaultTile : tileT
    , tiles : List tileT
    , width : Int
    , height : Int
    , getSocketIn : tileT -> Direction -> socketT
    , initialSeed : Seed
    }


init : TilesDefinition tileT socketT -> Model tileT socketT
init ({ width, height, tiles } as tilesDefinition) =
    Model
        { propGrid = Grid.repeat width height (superposition tiles)
        , openSteps = []
        , tilesDefinition = tilesDefinition
        , seed = tilesDefinition.initialSeed
        }


type alias ModelDetails tileT socketT =
    { propGrid : PropagationGrid
    , openSteps : List PropStep
    , tilesDefinition : TilesDefinition tileT socketT
    , seed : Seed
    }


type Direction
    = Top
    | Left
    | Bottom
    | Right


type PropagationTile
    = Fixed TileId
    | Superposition (List TileId)


type alias PropagationGrid =
    Grid PropagationTile


type alias TileId =
    Int


type alias Pos =
    ( Int, Int )


type PropStep
    = PickTile Pos TileId
    | KeepOnlyMatching Pos Pos


superposition : List tileT -> PropagationTile
superposition tileImages =
    Superposition <| List.range 0 (List.length tileImages)


findDirection : ( comparable, comparable ) -> ( comparable, comparable ) -> Direction
findDirection ( x0, y0 ) ( x1, y1 ) =
    if x1 > x0 then
        Right

    else if y1 > y0 then
        Bottom

    else if y0 > y1 then
        Top

    else
        Left


posInDir : Direction -> Pos -> Pos
posInDir dir ( x, y ) =
    case dir of
        Top ->
            ( x, y - 1 )

        Bottom ->
            ( x, y + 1 )

        Left ->
            ( x - 1, y )

        Right ->
            ( x + 1, y )


invert : Direction -> Direction
invert dir =
    case dir of
        Top ->
            Bottom

        Left ->
            Right

        Bottom ->
            Top

        Right ->
            Left


allDirections : List Direction
allDirections =
    [ Top, Left, Bottom, Right ]


canDock : ModelDetails tileT socketT -> Direction -> socketT -> Int -> Bool
canDock modelDetails dockDir dockSocket dockTileId =
    let
        dockTile =
            tileById modelDetails dockTileId

        currentSocket =
            modelDetails.tilesDefinition.getSocketIn dockTile dockDir
    in
    currentSocket == dockSocket


type alias Candidate =
    { pos : Pos
    , options : List TileId
    }


nextCandidates : ModelDetails tileT socketT -> List Candidate
nextCandidates { propGrid, tilesDefinition } =
    let
        gridWithIdx =
            Grid.indexedMap (\x y t -> ( x, y, t )) propGrid

        f ( x, y, t ) ( candidates, length ) =
            case t of
                Fixed _ ->
                    ( candidates, length )

                Superposition options ->
                    let
                        currentLength =
                            List.length options
                    in
                    if currentLength > length then
                        ( candidates, length )

                    else if currentLength < length then
                        ( [ { pos = ( x, y ), options = options } ]
                        , currentLength
                        )

                    else
                        ( { pos = ( x, y ), options = options } :: candidates
                        , currentLength
                        )
    in
    Tuple.first <| Grid.foldr f ( [], List.length tilesDefinition.tiles + 1 ) gridWithIdx


pickRandom : RandomPick -> ModelDetails tileT socketT -> ModelDetails tileT socketT
pickRandom ( posRand, tileRand ) modelDetails =
    let
        candidates =
            nextCandidates modelDetails

        pickRandomStep =
            if List.isEmpty candidates then
                []

            else
                let
                    randomCandidate =
                        List.head <| List.drop (modBy (List.length candidates) posRand) candidates
                in
                case randomCandidate of
                    Just { pos, options } ->
                        let
                            randomTileId =
                                List.head <| List.drop (modBy (List.length options) tileRand) options
                        in
                        case randomTileId of
                            Just tileId ->
                                [ PickTile pos tileId ]

                            Nothing ->
                                []

                    Nothing ->
                        []
    in
    { modelDetails
        | openSteps = pickRandomStep ++ modelDetails.openSteps
    }


processStep : ModelDetails tileT socketT -> PropStep -> PropagationGrid -> ( List PropStep, PropagationGrid )
processStep modelDetails step grid =
    case step of
        PickTile pos tileId ->
            let
                mkStep dir =
                    KeepOnlyMatching pos (posInDir dir pos)

                nextSteps =
                    List.map mkStep allDirections
            in
            ( nextSteps
            , Grid.set pos (Fixed tileId) grid
            )

        KeepOnlyMatching from to ->
            let
                originTile_ =
                    Grid.get from grid

                targetTile_ =
                    Grid.get to grid
            in
            case ( originTile_, targetTile_ ) of
                ( Just (Fixed originTileId), Just (Superposition options) ) ->
                    let
                        dir =
                            findDirection from to

                        originTile =
                            tileById modelDetails originTileId

                        originSocket =
                            modelDetails.tilesDefinition.getSocketIn originTile dir

                        revisedOptions =
                            List.filter (canDock modelDetails (invert dir) originSocket) options

                        updateGrid =
                            Grid.set to (Superposition revisedOptions) grid
                    in
                    ( [], updateGrid )

                _ ->
                    ( [], grid )


type alias RandomPick =
    ( Int, Int )


randomTileAndTileIdGen : ModelDetails tileT socketT -> Random.Generator ( Int, Int )
randomTileAndTileIdGen { tilesDefinition, propGrid } =
    let
        tileCount =
            Grid.width propGrid * Grid.height propGrid
    in
    Random.pair (Random.int 0 tileCount) (Random.int 0 (List.length tilesDefinition.tiles))


tileById : ModelDetails tileT socketT -> Int -> tileT
tileById { tilesDefinition } i =
    case List.head <| List.drop i tilesDefinition.tiles of
        Nothing ->
            tilesDefinition.defaultTile

        Just aTile ->
            aTile


viewPropGrid : (Pos -> TileId -> msg) -> (tileT -> Html msg) -> Model tileT socketT -> Html msg
viewPropGrid pickMsg displayTile (Model { propGrid, tilesDefinition }) =
    let
        mkNum options pos i =
            let
                attrs =
                    if List.member i options then
                        [ onClick (pickMsg pos i) ]

                    else
                        [ class "off" ]
            in
            div attrs [ text <| fromInt i ]

        viewTile row col propTile =
            case propTile of
                Fixed i ->
                    case List.head <| List.drop i tilesDefinition.tiles of
                        Just aTile ->
                            displayTile aTile

                        _ ->
                            displayTile tilesDefinition.defaultTile

                Superposition options ->
                    div [ class "superposition" ] <|
                        List.map (mkNum options ( col, row )) <|
                            List.range 0 (List.length tilesDefinition.tiles)

        viewRow row tiles =
            div [ class "row" ] <| Array.toList <| Array.indexedMap (viewTile row) tiles
    in
    div [] <| Array.toList <| Array.indexedMap viewRow <| Grid.rows propGrid
