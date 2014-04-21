## info command format:
## info time 203 nodes 11111111 score cp 11168 pv 5e9i+ ....

function rememberPV(gs::GameStatus)
    # remember the last PV, and also the 5 previous ones because 
    # they usually contain good moves to try
    i::Int = 0
    
    gs.lastPVLength = gs.triangularLength[1]
    #println("last length = ", gs.triangularLength[1])
    for i = 1:gs.triangularLength[1]
	gs.lastPV[i] = gs.triangularArray[1,i];
    end
end

# qui search
function Qui( gs::GameStatus, ply::Int, alpha::Int, beta::Int)
    movesfound::Int = 0
    gs.pvmovesfound = 0
    gs.triangularLength[ply+1] = ply
    teban::Int = ((ply & 0x1) == 0)?gs.side:((gs.side==SENTE)?GOTE:SENTE)
    ev = (teban == SENTE) ? 1: -1
    bestValue = -Infinity

    if (gs.inodes) & 1023 == 0
        now = time_ns()
        period::Int = now - gs.nsStart
        if period > MAXTHINKINGTIME
            gs.timedout = true
            return 0
        end
    end

    #x = -1 * ev * Eval( SENTE, gs.board, gs)
    x = ev * EvalBonanza( SENTE, gs.board, gs)
    if x >= beta
	return beta
    end
    if x > alpha
	alpha = x
    end
    if float(ply) > (gs.depth + 4.0) # changed!
	return x
    end

    movesfound = 0
    gs.pvmovesfound = 0
    gs.MoveBeginIndex = gs.moveBufLen[ply+1]
    gs.moveBufLen[ply+1+1] = generateQBB(gs.board, gs.moveBuf, teban, gs.moveBufLen[ply+1], gs)

    for i = gs.moveBufLen[ply+1]+1:gs.moveBufLen[ply+2] # 1 origin
        makeMove( gs.board, i, gs.moveBuf, teban)
        if in_check( teban, gs.board)
            #println("check!")
            takeBack( gs.board, i, gs.moveBuf, teban)
        else
            #if (seeMoveFlag(gs.moveBuf[i]) & (FLAG_NARI|FLAG_TORI)) == 0
            #    takeBack( gs.board, i, gs.moveBuf, teban)
            #    continue
            #end
            gs.inodes += 1
	    movesfound += 1
            val::Int = -Qui( gs, ply+1, -beta, -alpha)
            takeBack( gs.board, i, gs.moveBuf, teban)
            if gs.timedout
                return 0
            end
            if bestValue < val
                # both sides want to maximize from *their* perspective
                gs.pvmovesfound += 1
                gs.triangularArray[ply+1,ply+1] = gs.moveBuf[i]
		# save this move
                for j = (ply +1+1):gs.triangularLength[ply+1+1]
                    gs.triangularArray[ply+1,j] = gs.triangularArray[ply+1+1,j]
                    # and append the latest best PV from deeper plies
                end
                gs.triangularLength[ply+1] = gs.triangularLength[ply + 1+1]
                rememberPV(gs)
            end
            bestValue=max(val,bestValue)
            alpha = max( alpha, val)
            if alpha >= beta
                return beta
            end
        end
    end
    bestValue
end

# alpha-beta search
function AlphaBeta( gs::GameStatus, ply::Int, depth::Float64, alpha::Int, beta::Int)
    movesfound::Int = 0
    gs.pvmovesfound = 0
    gs.triangularLength[ply+1] = ply
    teban::Int = ((ply & 0x1) == 0)?gs.side:((gs.side==SENTE)?GOTE:SENTE)
    bestValue = -Infinity
    tt_flag::Int = TT_ALPHA
    tt_val::Int = 0
    tt_bestMove = Move(0,0,0,0,0,0)
    if depth <= 0.0
	gs.followpv = false
        return Qui( gs, ply, alpha, beta)
    end

    if (gs.inodes) & 1023 == 0
        now = time_ns()
        period::Int = now - gs.nsStart
        if period > MAXTHINKINGTIME
            gs.timedout = true
            return 0
        end
    end

    val, best, fl = tt_probe( depth, alpha, beta, gs)
    # if fl == TT_EXACT
    #     #return val
    # elseif fl == TT_ALPHA
    #     alpha = max(val,alpha)
    # elseif fl == TT_BETA
    #     beta = min(beta,val)
    # end

    if (!gs.followpv) && gs.allownull
        if true
            if in_check( teban, gs.board)
                gs.allownull = false
                gs.inodes += 1
                gs.board.nextMove $= 1
                val = -AlphaBeta( gs, ply, depth - NULLMOVE_REDUCTION, -beta, -beta+1)
                gs.board.nextMove $= 1
                if gs.timedout
                    return 0
                end
                gs.allownull = true
                if val >= beta
                    return val
                end
            else
            end
        end
    end

    # # IID
    # if (!gs.followpv) && gs.allownull
    #     gs.allownull = false
    #     gs.inodes += 1
    #     gs.board.nextMove $= 1
    #     val = -AlphaBeta( gs, ply, depth - NULLMOVE_REDUCTION, -beta, -alpha)
    #     gs.board.nextMove $= 1
    #     if gs.timedout
    #         return 0
    #     end
    #     gs.allownull = true
    #     if val >= beta
    #         return val
    #     end
    # end
    ev = (teban == SENTE)? 1: -1
    # tmpeval = ev * EvalBonanza( SENTE, gs.board, gs)

    #if (!gs.followpv) && gs.allownull && depth < 3.0 && ((tmpeval - 100.0 * depth) >= beta)
    # return int(tmpeval - 100.0*depth)
    #end

    movesfound = 0
    gs.pvmovesfound = 0
    gs.MoveBeginIndex = gs.moveBufLen[ply+1]
    gs.moveBufLen[ply+1+1] = generateBB(gs.board, gs.moveBuf, teban, gs.moveBufLen[ply+1], gs)

    beg = gs.moveBufLen[ply+1]+1
    for i = gs.moveBufLen[ply+1]+1:gs.moveBufLen[ply+2] # 1 origin
        if (i == beg)&&(best.move != 0)
            selectHash( gs, ply, i, depth, best)
        else
            selectmove( gs, ply, i, depth)
        end
        makeMove( gs.board, i, gs.moveBuf, teban)
        if in_check( teban, gs.board)
            #println("check!")
            takeBack( gs.board, i, gs.moveBuf, teban)
        else
            gs.inodes += 1
	    movesfound += 1
            ext = 0.0
	    if i > beg
                val = -AlphaBeta( gs, ply+1, depth-1.0+ext, -alpha-1, -alpha)
                if (val > alpha) && (val < beta)
                    val = -AlphaBeta( gs, ply+1, depth-1.0+ext, -beta, -alpha)
                end
            else
                val = -AlphaBeta( gs, ply+1, depth-1.0+ext, -beta, -alpha)
            end

            # original full depth search
            # val::Int = -AlphaBeta( gs, ply+1, depth-1.0, -beta, -alpha)

            takeBack( gs.board, i, gs.moveBuf, teban)
            if gs.timedout
                return 0
            end
            if bestValue < val
                # both sides want to maximize from *their* perspective
                gs.pvmovesfound += 1
                gs.triangularArray[ply+1,ply+1] = gs.moveBuf[i]
		# save this move
                for j = (ply +1+1):gs.triangularLength[ply+1+1]
                    gs.triangularArray[ply+1,j] = gs.triangularArray[ply+1+1,j]
                    # and append the latest best PV from deeper plies
                end
                gs.triangularLength[ply+1] = gs.triangularLength[ply + 1+1]
                rememberPV(gs)
                tt_flag = TT_ALPHA
                tt_val = alpha
                tt_bestMove = gs.moveBuf[i]
                tt_save( depth, tt_val, tt_flag, tt_bestMove, gs)
            end
            bestValue=max(val,bestValue)
            alpha = max( alpha, val)
            if alpha >= beta
                tt_flag = TT_BETA
                tt_val = beta
                tt_bestMove = gs.moveBuf[i]
                tt_save( depth, tt_val, tt_flag, gs.moveBuf[i], gs)
                return beta
            end
        end
    end
    if gs.pvmovesfound > 0
        if gs.board.nextMove == GOTE
            gs.blackHeuristics[seeMoveFrom(gs.triangularArray[ply+1,ply+1])+1,seeMoveTo(gs.triangularArray[ply+1,ply+1])+1] += int(depth*depth)
        else
            gs.whiteHeuristics[seeMoveFrom(gs.triangularArray[ply+1,ply+1])+1,seeMoveTo(gs.triangularArray[ply+1,ply+1])+1] += int(depth*depth)
        end
        tt_flag = TT_EXACT
        tt_save( depth, alpha, tt_flag, tt_bestMove, gs)
    end
    if movesfound == 0
        return -Infinity+ply-1
	#if in_check(teban, gs.board)
        #end
    end
    bestValue
end

# search driver
function think( sengo::Int, gs::GameStatus)
    move::Move = Move(0,0,0,0,0,0) # null move
    gs.lastPV = [Move(0,0,0,0,0,0) for x = 1:MaxPly]::Array{Move,1}
    gs.lastPVLength = 0
    gs.whiteHeuristics = [0 for x = 1:0xff, y = 1:0xff]::Array{Int,2}
    gs.blackHeuristics = [0 for x = 1:0xff, y = 1:0xff]::Array{Int,2}
    gs.nsStart = time_ns()
    gs.inodes = 0
    gs.timedout = false
    gs.side = sengo
    gs.board.nextMove = sengo

    for IDdepth = 1.0:1.0:15.0 #MaxPly
        gs.moveBufLen = [0 for x = 1:MaxPly]::Array{Int,1}
        gs.moveBuf = [Move(0,0,0,0,0,0) for x = 1:MaxMoves]        
        gs.triangularLength = [0 for x = 1:MaxPly]::Array{Int,1}
        gs.triangularArray  = [Move(0,0,0,0,0,0) for x = 1:MaxPly, y = 1:MaxPly]::Array{Move,2}
        gs.followpv = true
        gs.allownull = true
        gs.depth = IDdepth
        # score::Int = AlphaBeta(gs, 0, IDdepth,-Infinity,Infinity) # ply=0
        score::Int = PVS(gs, 0, IDdepth,-Infinity,Infinity) # ply=0
        # println("Depth = ", IDdepth, ", Score = ", score)
        if gs.timedout
            return gs.lastPV[1]
        end
        rememberPV(gs)
        timeInMSecs::Int = int((time_ns() - gs.nsStart)/1000000)
        NPS::Int = int(gs.inodes / ((time_ns() - gs.nsStart)/1000000000))
        ## info time 203 nodes 11111111 score cp 11168 pv 5e9i+ ....
        print("info time ",timeInMSecs," depth ", int(IDdepth), " nodes ", gs.inodes, " score cp ", score, " nps ",NPS," pv")
        for i = 1:gs.triangularLength[1]
	    print(" ",move2USIString(gs.lastPV[i]))
        end
        println()
    end
    move = gs.lastPV[1]
    return move
end

# search driver
function thinkASP( sengo::Int, gs::GameStatus)
    move::Move = Move(0,0,0,0,0,0) # null move
    gs.lastPV = [Move(0,0,0,0,0,0) for x = 1:MaxPly]::Array{Move,1}
    gs.lastPVLength = 0
    gs.whiteHeuristics = [0 for x = 1:0xff, y = 1:0xff]::Array{Int,2}
    gs.blackHeuristics = [0 for x = 1:0xff, y = 1:0xff]::Array{Int,2}
    gs.nsStart = time_ns()
    gs.inodes = 0
    gs.timedout = false
    gs.side = sengo
    gs.board.nextMove = sengo
    gs.tt = Dict{Uint64,TransP}()
    delta::Int = 80
    score::Int = 0
    middle::Int = 0
    smallAlpha::Int = 0
    smallBeta::Int  = 0
    for IDdepth = 1.0:1.0:30.0 #MaxPly
        hitScore::Bool = false

        while hitScore == false
            gs.moveBufLen = [0 for x = 1:MaxPly]::Array{Int,1}
            gs.moveBuf = [Move(0,0,0,0,0,0) for x = 1:MaxMoves]        
            gs.triangularLength = [0 for x = 1:MaxPly]::Array{Int,1}
            gs.triangularArray  = [Move(0,0,0,0,0,0) for x = 1:MaxPly, y = 1:MaxPly]::Array{Move,2}
            gs.followpv = true
            gs.allownull = true
            gs.MoveBeginIndex = 0

            # score::Int = AlphaBeta(gs, 0, IDdepth,-Infinity,Infinity) # ply=0
            if IDdepth == 1.0
                #score = PVS(gs, 0, IDdepth,-Infinity,Infinity,true) # ply=0
                score = AlphaBeta(gs, 0, IDdepth,-Infinity,Infinity) # ply=0
                middle = score
                hitScore = true
                smallAlpha = middle - delta
                smallBeta  = middle + delta
            else
                #score = PVS(gs, 0, IDdepth,smallAlpha,smallBeta,true) # ply=0
                score = AlphaBeta(gs, 0, IDdepth,smallAlpha,smallBeta) # ply=0
                middle = score

                if smallAlpha == -Infinity
                    hitScore = true
                end
                if smallBeta  == Infinity
                    hitScore = true
                end

                if smallAlpha < score < smallBeta
                    hitScore = true
                elseif score <= smallAlpha
                    delta *= 2
                    smallAlpha = middle - delta
                    if delta >= 2000
                        smallAlpha = -Infinity
                    end
                elseif score >= smallBeta
                    delta *= 2
                    smallBeta = middle + delta
                    if delta >= 2000
                        smallBeta = Infinity
                    end
                end
            end

            # println("Depth = ", IDdepth, ", Score = ", score)
            if gs.timedout
                return gs.lastPV[1]
            end
            rememberPV(gs)
            timeInMSecs::Int = int((time_ns() - gs.nsStart)/1000000)
            NPS::Int = int(gs.inodes / ((time_ns() - gs.nsStart)/1000000000))
            ## info time 203 nodes 11111111 score cp 11168 pv 5e9i+ ....
            print("info time ",timeInMSecs," depth ", int(IDdepth), " nodes ", gs.inodes, " score cp ", score, " nps ",NPS," pv")
            for i = 1:gs.triangularLength[1]
	        print(" ",move2USIString(gs.lastPV[i]))
            end
            println()
        end
    end
    move = gs.lastPV[1]
    return move
end

function ThinkTest(gs::GameStatus)
    m::Move = think(SENTE,gs)
end
